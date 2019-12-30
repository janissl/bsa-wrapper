#!/usr/bin/env perl

# (c) Microsoft Corporation. All rights reserved.

# Aligns parallel corpora using sentence lengths.  Approach is similar
# to IBM, except that pure empirical probabilities are used to
# estimate priors on sentence lengths, and a simple poisson
# distribution is used to estimate the probability of the length of a
# sentence based on the length of its translation. Paragraph breaks
# are ignored, and no anchor points are assumed.

# The search is an iterative, beam-pruned DP.  DP search is performed
# along the main diagonal of the alignment space, within the beam
# width.  The search is iteratively repeated, maintaining a fixed
# margin around the main diagonal, until the best path falls within a
# set bound of the margin everywhere.  Depending on a flag, bead
# probabilities are also re-estimated with each iteration, and
# iteration continues until bead probabilities converge.

# Confidence probabilities are computed for best path alignment using
# forward-backward algorithm.;

use strict;
use warnings;
use 5.014;

use File::Basename qw( basename );


my ($sent_file_1, $sent_file_2, $init_search_deviation, $min_beam_margin) = @ARGV;

my $sent_file_2_mod = basename($sent_file_2);

$init_search_deviation //= 20;
$min_beam_margin //= $init_search_deviation / 4;

my $start_time = (times)[0];
my $smooth_flag = 0;
my $iterate_flag = 0;
my $search_increment_ratio = 1.5;
my $high_prob_threshold = log(0.99);
my $conf_threshold = -20;
my $conf_increment_ratio = 1.15;
my $log_one_half = log(0.5);

my $peel_regex = '^[^\w\'\x{2019}]+|[^\w\'\x{2019}]+$';

open(my $in1, "<:encoding(UTF-8)", $sent_file_1) or
	die("cannot open data file $sent_file_1\n");

say "";
say "Reading $sent_file_1";


my (%length_cnt_1, %sent_length_1, %length_neg_log_prob_1, %cache);
my ($line, $num_words);
my $word_cnt_1 = 0;
my $sent_cnt_1 = 0;
my $skipped_lines_1 = 0;
my $skipping = 0;

while ($line = <$in1>) {
	chomp($line);

	if ($line eq '*|*|*') {
		$skipping = $skipping ? 0 : 1;
		next;
	}
	elsif ($skipping) {
		next;
	}

    $num_words = grep($_ =~ s/$peel_regex//ug ? $_ : $_, split(/\s+/, $line));

	if ($num_words) {
		$word_cnt_1 += $num_words;
		++$length_cnt_1{$num_words};
		$sent_length_1{$sent_cnt_1} = $num_words;
		++$sent_cnt_1;
	}
	else {
		++$skipped_lines_1;
	}
}

close($in1);

exit(0) unless $word_cnt_1 and $sent_cnt_1;

say "     $sent_cnt_1 good lines, $skipped_lines_1 lines skipped";

my ($length, $count);

$length_neg_log_prob_1{$length} = -log($count/$sent_cnt_1) while ($length, $count) = each %length_cnt_1;

open(my $in2, "<:encoding(UTF-8)", $sent_file_2) or
	die("cannot open data file $sent_file_2\n");

say "Reading $sent_file_2";

my (%length_cnt_2, %sent_length_2, %length_neg_log_prob_2, %target_pair_2_neg_log_prob);
my $word_cnt_2 = 0;
my $sent_cnt_2 = 0;
my $skipped_lines_2 = 0;
my $prev_length = 0;
$skipping = 0;

while ($line = <$in2>) {
	chomp($line);

	if ($line eq '*|*|*') {
		$skipping = $skipping ? 0 : 1;
		next;
	}
	elsif ($skipping) {
		next;
	}

	$num_words = grep($_ =~ s/$peel_regex//ug ? $_ : $_, split(/\s+/, $line));

	if ($num_words) {
		$word_cnt_2 += $num_words;
		++$length_cnt_2{$num_words};
		$sent_length_2{$sent_cnt_2} = $num_words;

		if ($sent_cnt_2 and $prev_length and $num_words) {
			undef $target_pair_2_neg_log_prob{$prev_length}{$num_words};
		}

		$prev_length = $num_words;
		++$sent_cnt_2;
	}
	else {
		++$skipped_lines_2;
	}
}

close($in2);

exit(0) unless $word_cnt_2 and $sent_cnt_2;

say "     $sent_cnt_2 good lines, $skipped_lines_2 lines skipped";

$length_neg_log_prob_2{$length} = -log($count / $sent_cnt_2) while ($length, $count) = each %length_cnt_2;

my (%normalizing_score, $first_length, $second_length, $ref);

while (($first_length, $ref) = each %target_pair_2_neg_log_prob) {
	foreach $second_length (keys %$ref) {
		undef $normalizing_score{$first_length + $second_length};
		$target_pair_2_neg_log_prob{$first_length}{$second_length} = $length_neg_log_prob_2{$first_length} + $length_neg_log_prob_2{$second_length};
	}
}

my ($length_sum, $i, $j, $score_1, $score_2);

foreach $length_sum (keys %normalizing_score) {
	for $i (1..$length_sum - 1) {
		$j = $length_sum - $i;
		if (defined($score_1 = $length_neg_log_prob_2{$i}) and
			defined($score_2 = $length_neg_log_prob_2{$j})) {
			$normalizing_score{$length_sum} += exp(-($score_1 + $score_2));
		}
	}
}

foreach $length_sum (keys %normalizing_score) {
	$normalizing_score{$length_sum} = -log($normalizing_score{$length_sum});
}

while (($first_length, $ref) = each %target_pair_2_neg_log_prob) {
	foreach $second_length (keys %$ref) {
		$target_pair_2_neg_log_prob{$first_length}{$second_length} -=
			$normalizing_score{$first_length + $second_length};
	}
}

my $mean_bead_length_ratio = ($word_cnt_2 / $sent_cnt_2)/($word_cnt_1 / $sent_cnt_1);

my $match_score_base = -log(.94);      # 1-1
my $contract_score_base = -log(.02);   # 2-1
my $expand_score_base = -log(.02);     # 1-2
my $delete_score_base = -log(.01);     # 1-0
my $insert_score_base = -log(.01);     # 0-1

my $sent_cnt_ratio = $sent_cnt_2 / $sent_cnt_1;
my $alignment_diffs = $sent_cnt_1;
my $max_path_deviation = $init_search_deviation / $search_increment_ratio;

my ($intermed_time_1, $intermed_time_2, $intermed_time_3, $pass_time);
my $backtrace;
my $search_deviation = 0;

$intermed_time_1 = (times)[0];
my $init_time = $intermed_time_1 - $start_time;

say "$init_time seconds initialization time";
say "";
say "Aligning sentences by length";

# Forward pass

say "";
say "Forward pass of forward-backward algorithm";
say "";

my (%forward_log_prob, @forward_log_probs, $forward_log_prob, $total_observation_log_prob);
my ($forward_prob_cnt, $old_backtrace);
my ($lower_limit, $upper_limit, $margin_limit);
my ($pos_1, $pos_2, $diagonal_pos);
my ($pos_1_minus_1, $pos_1_minus_2, $length_pos_1_minus_1, $length_pos_1_minus_2);
my ($pos_2_minus_1, $pos_2_minus_2, $length_pos_2_minus_1, $length_pos_2_minus_2);
my ($length_pair_1, $length_neg_log_prob_pos_1_minus_1, $length_neg_log_prob_pos_1_minus_2);
my ($best_score, $best_bead_score, $best_bead);
my ($new_score, $new_bead_score, $bead);
my (%bead_type_cnt, $total_bead_cnt, $deviation);
my ($print_ctr);
my $iteration = 0;

$conf_threshold /= $conf_increment_ratio;

while (($alignment_diffs and $iterate_flag) or
		(($max_path_deviation + $min_beam_margin) > $search_deviation)) {
	$intermed_time_1 = (times)[0];
	$search_deviation = $max_path_deviation * $search_increment_ratio;
	$conf_threshold *= $conf_increment_ratio;
	$margin_limit = $max_path_deviation + $min_beam_margin;
	$search_deviation = $margin_limit if $margin_limit > $search_deviation;
	++$iteration;

	say "Iteration $iteration with search deviation $search_deviation";
	say "";

	undef %forward_log_prob;
	$forward_log_prob{0}{0} = 0;
	$forward_prob_cnt = 0;

	$old_backtrace = $backtrace;
	undef $backtrace;

	$pos_1 = 0;
	$print_ctr = 0;

	while ($pos_1 <= $sent_cnt_1) {
		$diagonal_pos = int(($sent_cnt_ratio * $pos_1) + 0.000001);

		$lower_limit = int($diagonal_pos - $search_deviation);
		$lower_limit = 0 if $lower_limit < 0;

		$upper_limit = int($diagonal_pos + $search_deviation);
		$upper_limit = $sent_cnt_2 if $upper_limit > $sent_cnt_2;

		if ($print_ctr == 100) {
			print "\rposition $pos_1, $lower_limit-$upper_limit";
			$print_ctr = 0;
		}

		$pos_1_minus_1 = $pos_1 - 1;
		$pos_1_minus_2 = $pos_1 - 2;
		$length_pos_1_minus_1 = $sent_length_1{$pos_1_minus_1} // 0;
		$length_pos_1_minus_2 = $sent_length_1{$pos_1_minus_2} // 0;

		$length_pair_1 = $length_pos_1_minus_1 + $length_pos_1_minus_2;
		$length_neg_log_prob_pos_1_minus_1 = $length_neg_log_prob_1{$length_pos_1_minus_1};
		$length_neg_log_prob_pos_1_minus_2 = $length_neg_log_prob_1{$length_pos_1_minus_2};

		($best_bead_score, $best_bead) = (undef, undef);

		foreach $pos_2 ($lower_limit .. $upper_limit) {
			$pos_2_minus_1 = $pos_2 - 1;
			$pos_2_minus_2 = $pos_2 - 2;

			$length_pos_2_minus_1 = $sent_length_2{$pos_2_minus_1};
			$length_pos_2_minus_2 = $sent_length_2{$pos_2_minus_2};

			undef @forward_log_probs;
			undef $best_score;

			if (defined($forward_log_prob = $forward_log_prob{$pos_1_minus_1}{$pos_2})) {
				$new_bead_score = $delete_score_base + $length_neg_log_prob_pos_1_minus_1;
				$new_score = $new_bead_score - $forward_log_prob;
				push(@forward_log_probs, -$new_score);

				if (not defined $best_score or $new_score < $best_score) {
					$best_score = $new_score;
					$best_bead_score = $new_bead_score; # JS: appears useless
					$best_bead = 'delete';
				}
			}

			if (defined($forward_log_prob = $forward_log_prob{$pos_1}{$pos_2_minus_1})) {
				$new_bead_score = $insert_score_base + $length_neg_log_prob_2{$length_pos_2_minus_1};
				$new_score = $new_bead_score - $forward_log_prob;
				push(@forward_log_probs, -$new_score);

				if (not defined $best_score or $new_score < $best_score) {
					$best_score = $new_score;
					$best_bead_score = $new_bead_score; # JS: appears useless
					$best_bead = 'insert';
				}
			}

			if (defined($forward_log_prob = $forward_log_prob{$pos_1_minus_1}{$pos_2_minus_1})) {
				$new_bead_score = $match_score_base +
					$length_neg_log_prob_pos_1_minus_1 +
					length_neg_log_cond_prob_2($length_pos_1_minus_1, $length_pos_2_minus_1);
				$new_score = $new_bead_score - $forward_log_prob;
				push(@forward_log_probs, -$new_score);

				if (not defined $best_score or $new_score < $best_score) {
					$best_score = $new_score;
					$best_bead_score = $new_bead_score; # JS: appears useless
					$best_bead = 'match';
				}
			}

			if (defined($forward_log_prob = $forward_log_prob{$pos_1_minus_2}{$pos_2_minus_1})) {
				$new_bead_score = $contract_score_base +
					$length_neg_log_prob_pos_1_minus_1 +
					$length_neg_log_prob_pos_1_minus_2 +
					length_neg_log_cond_prob_2($length_pair_1, $length_pos_2_minus_1);
				$new_score = $new_bead_score - $forward_log_prob;
				push(@forward_log_probs, -$new_score);

				if (not defined $best_score or $new_score < $best_score) {
					$best_score = $new_score;
					$best_bead_score = $new_bead_score; # JS: appears useless
					$best_bead = 'contract';
				}
			}

			if (defined($forward_log_prob = $forward_log_prob{$pos_1_minus_1}{$pos_2_minus_2})) {
				unless (defined $target_pair_2_neg_log_prob{$length_pos_2_minus_2}{$length_pos_2_minus_1}) {
					warn "ERROR: no normalization for expand pair";
				}

				$new_bead_score = $expand_score_base +
					$length_neg_log_prob_1{$length_pos_1_minus_1} +
					$target_pair_2_neg_log_prob{$length_pos_2_minus_2}{$length_pos_2_minus_1} +
					length_neg_log_cond_prob_2($length_pos_1_minus_1,
						$length_pos_2_minus_1 + $length_pos_2_minus_2);
				$new_score = $new_bead_score - $forward_log_prob;
				push(@forward_log_probs, -$new_score);

				if (not defined $best_score or $new_score < $best_score) {
					$best_score = $new_score;
					$best_bead_score = $new_bead_score;
					$best_bead = 'expand';
				}
			}

			if (defined($best_score)) {
				$forward_log_prob{$pos_1}{$pos_2} = log_add_list(@forward_log_probs);
				++$forward_prob_cnt;
				$$backtrace{$pos_1}{$pos_2} = $best_bead;
			}
		}
		++$print_ctr;
		++$pos_1;
	}

	--$pos_1;
	say "\rposition $pos_1, $lower_limit-$upper_limit";

	$total_observation_log_prob = $forward_log_prob{$sent_cnt_1}{$sent_cnt_2};

	say "Forward probs computed: $forward_prob_cnt";
	say "End to end forward score: $total_observation_log_prob";

	undef %bead_type_cnt;

	if ($smooth_flag) {
		$total_bead_cnt = 1000;  # smoothing by adding 1000 counts in original distribution
	}
	else {
		$total_bead_cnt = 5;  # add-one smoothing for 5 bead types
	}

	$max_path_deviation = 0;
	$alignment_diffs = 0;
	$pos_1 = $sent_cnt_1;
	$pos_2 = $sent_cnt_2;

	until ($pos_1 == 0 and $pos_2 == 0) {
		$deviation = abs(int(($sent_cnt_ratio * $pos_1) + 0.000001) - $pos_2);
		$max_path_deviation = $deviation if $deviation > $max_path_deviation;
		$bead = $$backtrace{$pos_1}{$pos_2};

		++$alignment_diffs if defined($$old_backtrace{$pos_1}{$pos_2}) and $bead ne $$old_backtrace{$pos_1}{$pos_2};
		++$bead_type_cnt{$bead} if $bead;
		++$total_bead_cnt if $bead;

		if (defined $bead and $bead eq 'match') {
			--$pos_1;
			--$pos_2;
		}
		elsif (defined $bead and $bead eq 'contract') {
			$pos_1 -= 2;
			--$pos_2;
		}
		elsif (defined $bead and $bead eq 'expand') {
			--$pos_1;
			$pos_2 -= 2;
		}
		elsif (defined $bead and $bead eq 'delete') {
			--$pos_1;
		}
		elsif (defined $bead and $bead eq 'insert') {
			--$pos_2;
		}
		else {
            warn "ERROR: Bead |$bead| unrecognized at ($pos_1, $pos_2)\n";
            exit(1);
		}
	}

	say "max deviation: $max_path_deviation";
	say "$alignment_diffs alignment differences";
	say "";
	say "$total_bead_cnt total beads:";
	say "  $count $bead" while ($bead, $count) = each %bead_type_cnt;

	$intermed_time_2 = (times)[0];
	$pass_time = $intermed_time_2 - $intermed_time_1;

	say "$pass_time seconds forward pass time";
	say "";

	if ($iterate_flag) {
		if ($smooth_flag) {
			$match_score_base = -log(($bead_type_cnt{'match'} + 940) / $total_bead_cnt);        # 1-1
			$contract_score_base = -log(($bead_type_cnt{'contract'} + 20) / $total_bead_cnt);   # 2-1
			$expand_score_base = -log(($bead_type_cnt{'expand'} + 20) / $total_bead_cnt);       # 1-2
			$delete_score_base = -log(($bead_type_cnt{'delete'} + 10) / $total_bead_cnt);       # 1-0
			$insert_score_base = -log(($bead_type_cnt{'insert'} + 10) / $total_bead_cnt);       # 0-1
		}
		else {
			$match_score_base = -log(($bead_type_cnt{'match'} + 1) / $total_bead_cnt);         # 1-1
			$contract_score_base = -log(($bead_type_cnt{'contract'} + 1) / $total_bead_cnt);   # 2-1
			$expand_score_base = -log(($bead_type_cnt{'expand'} + 1) / $total_bead_cnt);       # 1-2
			$delete_score_base = -log(($bead_type_cnt{'delete'} + 1) / $total_bead_cnt);       # 1-0
			$insert_score_base = -log(($bead_type_cnt{'insert'} + 1) / $total_bead_cnt);       # 0-1
		}
	}
}

# Backward pass

say "Backward pass of forward-backward algorithm with $conf_threshold pruning threshold";
say "";

my (@backtrace_list, %backward_log_prob, $backward_log_prob, @backward_log_probs, $norm_forward_log_prob);
my ($backward_prob_cnt_diff, $bead_backward_log_prob, $bead_total_log_prob, $total_log_prob, $prob);
my ($pos_1_plus_1, $pos_1_plus_2, $length_pos_1, $length_pos_1_plus_1);
my ($pos_2_plus_1, $length_pos_2, $length_pos_2_plus_1);
my ($length_neg_log_prob_pos_1, $length_neg_log_prob_pos_1_plus_1);
my $high_prob_match_cnt = 0;
my $backward_prob_cnt = 0;
my $saved_backward_prob_cnt = 0;
my $old_backward_prob_cnt = 0;

undef %bead_type_cnt;
$backward_log_prob{$sent_cnt_1}{$sent_cnt_2} = 0;
$pos_1 =  $sent_cnt_1 + 1;
$total_bead_cnt = 0;
$print_ctr = 0;

while ($pos_1 > 0) {
	--$pos_1;
	$diagonal_pos = int(($sent_cnt_ratio * $pos_1) + 0.000001);

	$lower_limit = int($diagonal_pos - $search_deviation);
	$lower_limit = 0 if $lower_limit < 0;

	$upper_limit = int($diagonal_pos + $search_deviation);
	$upper_limit = $sent_cnt_2 if $upper_limit > $sent_cnt_2;

	$pos_1_plus_1 = $pos_1 + 1;
	$pos_1_plus_2 = $pos_1 + 2;
	$length_pos_1 = $sent_length_1{$pos_1} // 0;
	$length_pos_1_plus_1 = $sent_length_1{$pos_1_plus_1} // 0;

	$backward_prob_cnt_diff = $backward_prob_cnt - $old_backward_prob_cnt;

	if ($print_ctr == 100) {
		print "\rposition $pos_1, $lower_limit-$upper_limit, $backward_prob_cnt_diff";
		$print_ctr = 0;
	}

	$old_backward_prob_cnt = $backward_prob_cnt;
	++$print_ctr;

	$length_pair_1 = $length_pos_1 + $length_pos_1_plus_1;
	$length_neg_log_prob_pos_1 = $length_neg_log_prob_1{$length_pos_1};
	$length_neg_log_prob_pos_1_plus_1 = $length_neg_log_prob_1{$length_pos_1_plus_1};

	for $pos_2 (reverse $lower_limit..$upper_limit) {
		$pos_2_plus_1 = $pos_2 + 1;
		$length_pos_2 = $sent_length_2{$pos_2};
		$length_pos_2_plus_1 = $sent_length_2{$pos_2_plus_1};

		$norm_forward_log_prob = $forward_log_prob{$pos_1}{$pos_2} - $total_observation_log_prob;

		undef @backward_log_probs;

		if (defined($backward_log_prob = $backward_log_prob{$pos_1_plus_1}{$pos_2})) {
			$new_bead_score = $delete_score_base +
				$length_neg_log_prob_pos_1;

			$bead_backward_log_prob = $backward_log_prob - $new_bead_score;

			$bead_total_log_prob = $bead_backward_log_prob + $norm_forward_log_prob;

			if ($bead_total_log_prob > $log_one_half) {
				push(@backtrace_list, [$pos_1, $pos_2, 'delete', exp($bead_total_log_prob)]);
				++$bead_type_cnt{'delete'};
				++$total_bead_cnt;
			}

			push(@backward_log_probs, $bead_backward_log_prob);
		}

		if (defined($backward_log_prob = $backward_log_prob{$pos_1}{$pos_2_plus_1})) {
			$new_bead_score = $insert_score_base +
				$length_neg_log_prob_2{$length_pos_2};
			$bead_backward_log_prob = $backward_log_prob - $new_bead_score;
			$bead_total_log_prob = $bead_backward_log_prob + $norm_forward_log_prob;

			if ($bead_total_log_prob > $log_one_half) {
				push(@backtrace_list, [$pos_1, $pos_2, 'insert', exp($bead_total_log_prob)]);
				++$bead_type_cnt{'insert'};
				++$total_bead_cnt;
			}

			push(@backward_log_probs, $bead_backward_log_prob);
		}

		if (defined($backward_log_prob = $backward_log_prob{$pos_1_plus_1}{$pos_2_plus_1})) {
			$new_bead_score = $match_score_base +
				$length_neg_log_prob_pos_1 +
				length_neg_log_cond_prob_2($length_pos_1, $length_pos_2);
			$bead_backward_log_prob = $backward_log_prob - $new_bead_score;
			$bead_total_log_prob = $bead_backward_log_prob + $norm_forward_log_prob;

			if ($bead_total_log_prob > $log_one_half) {
				push(@backtrace_list, [$pos_1, $pos_2, 'match', exp($bead_total_log_prob)]);
				++$bead_type_cnt{'match'};
				++$total_bead_cnt;

				if ($bead_total_log_prob > $high_prob_threshold) {
					++$high_prob_match_cnt;
				}
			}

			push(@backward_log_probs, $bead_backward_log_prob);
		}

		if (defined($backward_log_prob = $backward_log_prob{$pos_1_plus_2}{$pos_2_plus_1})) {
			$new_bead_score = $contract_score_base +
				$length_neg_log_prob_pos_1 +
				$length_neg_log_prob_pos_1_plus_1 +
				length_neg_log_cond_prob_2($length_pair_1, $length_pos_2);
			$bead_backward_log_prob = $backward_log_prob - $new_bead_score;
			$bead_total_log_prob = $bead_backward_log_prob + $norm_forward_log_prob;

			if ($bead_total_log_prob > $log_one_half) {
				push(@backtrace_list, [$pos_1, $pos_2, 'contract', exp($bead_total_log_prob)]);
				++$bead_type_cnt{'contract'};
				++$total_bead_cnt;
			}

			push(@backward_log_probs, $bead_backward_log_prob);
		}

		if (defined($backward_log_prob = $backward_log_prob{$pos_1_plus_1}{$pos_2 + 2})) {
			$new_bead_score = $expand_score_base +
				$length_neg_log_prob_pos_1 +
				$target_pair_2_neg_log_prob{$length_pos_2}{$length_pos_2_plus_1} +
				length_neg_log_cond_prob_2($length_pos_1, $length_pos_2 + $length_pos_2_plus_1);
			$bead_backward_log_prob = $backward_log_prob - $new_bead_score;
			$bead_total_log_prob = $bead_backward_log_prob + $norm_forward_log_prob;

			if ($bead_total_log_prob > $log_one_half) {
				push(@backtrace_list, [$pos_1, $pos_2, 'expand', exp($bead_total_log_prob)]);
				++$bead_type_cnt{'expand'};
				++$total_bead_cnt;
			}

			push(@backward_log_probs, $bead_backward_log_prob);
		}

		if (@backward_log_probs) {
			++$backward_prob_cnt;
			$backward_log_prob = log_add_list(@backward_log_probs);
			$total_log_prob = $backward_log_prob + $norm_forward_log_prob;

			if ($total_log_prob > $conf_threshold) {
				++$saved_backward_prob_cnt;
				$backward_log_prob{$pos_1}{$pos_2} = $backward_log_prob;
			}
		}
	}
}

say "\rposition $pos_1, $lower_limit-$upper_limit         ";
say "Backward probs computed: $backward_prob_cnt";
say "Backward probs saved: $saved_backward_prob_cnt";
say "End to end backward score: $backward_log_prob{0}{0}";
say "";
say "$total_bead_cnt total beads:";
say "  $count $bead" while ($bead, $count) = each %bead_type_cnt;
say "$high_prob_match_cnt high prob matches";

$intermed_time_3 = (times)[0];
$pass_time = $intermed_time_3 - $intermed_time_2;
say "$pass_time seconds backward pass time";

open(my $out, ">:encoding(UTF-8)", "$sent_file_1.$sent_file_2_mod.length-backtrace") or die "Failed to create '$sent_file_1.$sent_file_2_mod.length-backtrace'!\n$!";

while (@backtrace_list) {
	($pos_1, $pos_2, $bead, $prob) = @{pop(@backtrace_list)};
	next unless defined $pos_1 and defined $pos_2 and defined $bead and defined $prob and $prob =~ /^\d{1,10}[.,]\d+$/;
	printf $out "%6d %6d %-8s %10.8f\n", $pos_1, $pos_2, $bead, $prob;
}

close($out);

open(my $search, ">:encoding(UTF-8)", "$sent_file_1.$sent_file_2_mod.search-nodes") or die "Failed to create '$sent_file_1.$sent_file_2_mod.search-nodes'!\n$!";

while (($pos_1, $ref) = each %backward_log_prob) {
	foreach $pos_2 (keys %{$ref}) {
		say $search "$pos_1 $pos_2";
	}
}

close($search);

my $final_time = (times)[0];
my $total_time = $final_time - $start_time;
say "";
say "$total_time seconds total time";

# ==============================================================================
sub length_neg_log_cond_prob_2 {
    my ($length1, $length2) = @_;

    unless (defined $cache{$length1}{$length2}) {
        my $mean = $length1 * $mean_bead_length_ratio;
        fill_in_missing_neg_log_probs($length1, $length2, $mean, log($mean));
    }

    return $cache{$length1}{$length2};
}

sub get_lowest_length2 {
    my ($length1, $length2) = @_;
    my $lowest_length = 0;

    unless (defined $cache{$length1}{$length2}) {
        foreach my $len2 (reverse 0..$length2) {
            if (defined $cache{$length1}{$len2}) {
                $lowest_length = $len2;
                last;
            }
        }
    }

    return $lowest_length;
}


sub fill_in_missing_neg_log_probs {
    my ($length1, $length2, $mean, $log_mean) = @_;

    my $lowest_length2 = get_lowest_length2($length1, $length2);

    if ($lowest_length2 == 0) {
        ++$lowest_length2;
        $cache{$length1}{$lowest_length2} = $mean - $log_mean;
    }

    foreach my $len2 ($lowest_length2 + 1..$length2) {
        $cache{$length1}{$len2} = $cache{$length1}{$len2 - 1} + log($len2) - $log_mean;
    }
}


sub log_add_list {
	my ($log_y, @log_x_list) = @_;

	return unless defined $log_y;
	return $log_y if @log_x_list == 0;

	my ($log_x, @new_log_x_list);

	foreach $log_x (@log_x_list) {
		if ($log_x > $log_y) {
			push(@new_log_x_list, $log_y);
			$log_y = $log_x;
		}
		else {
			push(@new_log_x_list, $log_x);
		}
	}

	my $x_div_y_sum_plus_1 = 1;

	foreach $log_x (@new_log_x_list) {
		$x_div_y_sum_plus_1 += exp($log_x - $log_y);
	}

	return $log_y + log($x_div_y_sum_plus_1);
}
