#!/usr/bin/env perl

# (c) Microsoft Corporation. All rights reserved.

# Aligns parallel corpora using sentence lengths, using both sentence
# lengths and word associations.  The idea is to first align on the
# basis of sentence lengths; use the highest probability matches to
# generate word association probabilities, (using IBM model 1), and
# then re-align using the word association probabilities.  The
# word-based alignment is much slower that the length-based alignment,
# but we limit the application of the word-based model to plausible
# alignments produced by the length-based method, so in practice it
# doesn't take that much longer.

# This version handles the iteration over the sentence file pairs, so
# that the word translation file only needs to be loaded once.

use strict;
use warnings;
use 5.014; # necessary for supporting Unicode in regexes


my ($init_search_deviation, $min_beam_margin) = @ARGV;

$init_search_deviation //= 20;
$min_beam_margin //= $init_search_deviation / 4;

my $start_time = (times)[0];
my $smooth_flag = 0;
my $iterate_flag = 0;
my $increment_ratio = 1.5;
my $high_prob_threshold = 0.99;
my $log_high_prob_threshold = log($high_prob_threshold);
my $conf_threshold = -20;
my $conf_threshold_prob = exp($conf_threshold);
my $log_one_half = log(0.5);
my $bead_type_diff_threshold = 0.0001;

my (%trans_prob, %type_1, %type_2, $line, $prob, $token_1, $token_2);
my $word_assoc_cnt = 0;

my $peel_regex = '^[^\w\'\x{2019}]+|[^\w\'\x{2019}]+$';

open(my $model, "<:encoding(UTF-8)", "model-one") or
	die("cannot open data file model-one\n");

say "";
say "Reading model-one";

while ($line = <$model>) {
	($prob, $token_1, $token_2) = split(' ', $line);
	$trans_prob{$token_1}{$token_2} = $prob;
	$type_1{$token_1} = 1;
	$type_2{$token_2} = 1;
	++$word_assoc_cnt;
}

close($model);

say "     $word_assoc_cnt word associations";

my (%length_cnt_1, %sent_length_1, %token_cnt_1, %words_1, %token_score_1, %length_neg_log_prob_1);
my (%length_cnt_2, %sent_length_2, %token_cnt_2, %words_2, %token_score_2, %length_neg_log_prob_2);
my (%target_pair_2_neg_log_prob, %normalizing_score, %length_backward_log_prob, %bead_score, %cache);
my (@forward_log_probs, $forward_log_prob, %forward_log_prob, %backward_log_prob, @backward_log_probs);
my (%bead_type_cnt, $bead_length_backward_log_prob, $bead_total_log_prob);
my ($norm_forward_log_prob, @length_backward_log_probs, $length_backward_log_prob, $backtrace_cnt);
my ($backward_log_prob, $bead_backward_log_prob, $bead_total_prob, $bead_type, $old_bead_type_total_score);
my ($high_prob_match_cnt, $backward_prob_cnt, $saved_backward_prob_cnt, $deviation);
my ($intermed_time_1, $intermed_time_2, $intermed_time_3, $intermed_time_4, $intermed_time_5);
my ($init_time, $pass_time, $final_time, $total_time);
my ($sent_line, $sent_file_1, $sent_file_2, $in1, $in2, $nodes, $out);
my ($sent_cnt_1, $word_cnt_1, $skipped_lines_1, $skipping);
my ($sent_cnt_2, $word_cnt_2, $skipped_lines_2, $prev_length);
my (@words, $num_words, $word, $count, $length);
my ($first_length, $second_length, $ref, $score_sum, $length_sum, $i, $j);
my ($score_1, $score_2, $sent_cnt_ratio, $node_count, $align_by_length);
my ($match_score_base, $contract_score_base, $expand_score_base, $delete_score_base, $insert_score_base);
my ($pos_1, $pos_2, $margin_limit, $lower_limit, $upper_limit, $diagonal_pos);
my ($total_observation_log_prob, $alignment_diffs, $max_path_deviation, $search_deviation, $iteration);
my ($forward_prob_cnt, $backtrace, $old_backtrace, @backtrace_list);
my ($pos_1_minus_1, $pos_1_minus_2, $length_pos_1_minus_1, $length_pos_1_minus_2);
my ($pos_2_minus_1, $pos_2_minus_2, $length_pos_2_minus_1, $length_pos_2_minus_2);
my ($length_pair_1, $length_neg_log_prob_pos_1_minus_1, $length_neg_log_prob_pos_1_minus_2);
my ($best_score, $best_bead_score, $best_bead);
my ($new_score, $new_bead_score, $bead, $total_bead_cnt, $bead_type_total_score);
my ($pos_1_plus_1, $pos_1_plus_2, $length_pos_1, $length_pos_1_plus_1);
my ($pos_2_plus_1, $pos_2_plus_2, $length_pos_2, $length_pos_2_plus_1);
my ($words_pos_1_minus_1, $words_pos_1_minus_2, $words_pair_1);
my ($word_seq_score_pos_1_minus_1, $word_seq_score_pos_1_minus_2);
my ($words_pos_2_minus_1, $words_pos_2_minus_2);
my $print_ctr;
my $mean_bead_length_ratio = 1;

open(my $sents, "<:encoding(UTF-8)", "sentence-file-pair-list") or
	die("cannot open data file sentence-file-pair-list\n");

$intermed_time_1 = (times)[0];
$init_time = $intermed_time_1 - $start_time;

say "$init_time seconds global initialization time";
say "";
say "========================================================";
say "";

while ($sent_line = <$sents>) {
	($sent_file_1, $sent_file_2) = split(' ', $sent_line);

	open($in1, "<:encoding(UTF-8)", $sent_file_1) or
		die("cannot open data file $sent_file_1\n");

	$start_time = (times)[0];

	undef %length_cnt_1;
	undef %sent_length_1;
	undef %token_cnt_1;
	undef %words_1;
	undef %token_score_1;
	undef %length_neg_log_prob_1;
	undef %length_cnt_2;
	undef %sent_length_2;
	undef %token_cnt_2;
	undef %words_2;
	undef %token_score_2;
	undef %length_neg_log_prob_2;
	undef %target_pair_2_neg_log_prob;
	undef %normalizing_score;
	undef %length_backward_log_prob;
	undef %bead_score;
	undef %cache;

	say "Reading $sent_file_1";

	$sent_cnt_1 = 0;
	$word_cnt_1 = 0;
	$skipped_lines_1 = 0;
	$skipping = 0;

	while ($line = <$in1>) {
		chomp($line);

		if ($line eq '*|*|*') {
			$skipping = $skipping ? 0 : 1;
			next;
		}
		elsif ($skipping) {
			next;
		}

        @words = grep($_ =~ s/$peel_regex//ug ? $_ : $_, split(/\s+/, $line));
		$num_words = @words;

		if ($num_words) {
			$word_cnt_1 += $num_words;
			++$length_cnt_1{$num_words};
			$sent_length_1{$sent_cnt_1} = $num_words;

			foreach $word (@words) {
				if ($word =~ /\w/u) {
					$word =~ /\W*(\w.*\w|\w)/u;
					$word = lc($1);
				}
				else {
					$word =~ /^([^\)]*)/;
					$word = $1;
					$word = '(null)' unless $word;
				}

				unless (exists($type_1{$word})) {
					$word = '(other)';
				}

				++$token_cnt_1{$word};
			}

			$words_1{$sent_cnt_1} = [@words];
			++$sent_cnt_1;
		}
		else {
			++$skipped_lines_1;
		}
	}

	close($in1);

	next unless $word_cnt_1 and $sent_cnt_1;

	say "     $sent_cnt_1 good lines, $skipped_lines_1 lines skipped";

	$token_score_1{$word} = -log($count/$word_cnt_1) while ($word, $count) = each %token_cnt_1;

	undef %token_cnt_1;

	$length_neg_log_prob_1{$length} = -log($count/$sent_cnt_1) while ($length, $count) = each %length_cnt_1;

	open($in2, "<:encoding(UTF-8)", $sent_file_2) or
		die("cannot open data file $sent_file_2\n");

	say "Reading $sent_file_2";

	$sent_cnt_2 = 0;
	$word_cnt_2 = 0;
	$skipped_lines_2 = 0;
	$prev_length = 0;
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

        @words = grep($_ =~ s/$peel_regex//ug ? $_ : $_, split(/\s+/, $line));
		$num_words = @words;

		if ($num_words) {
			$word_cnt_2 += $num_words;
			++$length_cnt_2{$num_words};
			$sent_length_2{$sent_cnt_2} = $num_words;

			if ($sent_cnt_2 and $prev_length and $num_words) {
				undef $target_pair_2_neg_log_prob{$prev_length}{$num_words};
			}

			$prev_length = $num_words;

			foreach $word (@words) {
				if ($word =~ /\w/u) {
					$word =~ /\W*(\w.*\w|\w)/u;
					$word = lc($1);
				}
				else {
					$word =~ /^([^\)]*)/;
					$word = $1;
					$word = '(null)' unless $word;
				}

				unless (exists($type_2{$word})) {
					$word = '(other)';
				}

				++$token_cnt_2{$word};
			}

			$words_2{$sent_cnt_2} = [@words];
			++$sent_cnt_2;
		}
		else {
			++$skipped_lines_2;
		}
	}

	close($in2);

	next unless $word_cnt_2 and $sent_cnt_2;

	say "     $sent_cnt_2 good lines, $skipped_lines_2 lines skipped";

	$token_score_2{$word} = -log($count/$word_cnt_2) while ($word, $count) = each %token_cnt_2;

	undef %token_cnt_2;

	$length_neg_log_prob_2{$length} = -log($count/$sent_cnt_2) while ($length, $count) = each %length_cnt_2;

	while (($first_length, $ref) = each %target_pair_2_neg_log_prob) {
		foreach $second_length (keys %$ref) {
			$score_sum = $length_neg_log_prob_2{$first_length} + $length_neg_log_prob_2{$second_length};
			undef $normalizing_score{$first_length+$second_length};
			$target_pair_2_neg_log_prob{$first_length}{$second_length} = $score_sum;
		}
	}

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

	$mean_bead_length_ratio = ($word_cnt_2/$sent_cnt_2)/($word_cnt_1/$sent_cnt_1);

	$match_score_base = -log(.94);      # 1-1
	$contract_score_base = -log(.02);   # 2-1
	$expand_score_base = -log(.02);     # 1-2
	$delete_score_base = -log(.01);     # 1-0
	$insert_score_base = -log(.01);     # 0-1

	$sent_cnt_ratio = $sent_cnt_2 / $sent_cnt_1;
	$node_count = 0;

	if (open($nodes, "<:encoding(UTF-8)", "$sent_file_1.$sent_file_2.search-nodes")) {
		$align_by_length = 0;
		say "Reading $sent_file_1.$sent_file_2.search-nodes";

		while ($line = <$nodes>) {
			($pos_1, $pos_2) = split(' ', $line);

			next unless defined $pos_2;

			$length_backward_log_prob{$pos_1}{$pos_2} = 1;
			++$node_count;
		}

		close($nodes);

		say "     $node_count search nodes";
	}
	else {
		$align_by_length = 1;
	}

	$intermed_time_1 = (times)[0];
	$init_time = $intermed_time_1 - $start_time;
	say "$init_time seconds initialization time";

	if ($align_by_length) {
		say "";
		say "ALIGNING SENTENCES BY LENGTH";

		# Forward pass

		say "";
		say "Forward pass of forward-backward algorithm";
		say "";

		$alignment_diffs = $sent_cnt_1;
		undef $backtrace;
		$max_path_deviation = $init_search_deviation / $increment_ratio;
		$search_deviation = 0;
		$iteration = 0;

		while (($max_path_deviation + $min_beam_margin) > $search_deviation) {
			$intermed_time_1 = (times)[0];

			$search_deviation = $max_path_deviation * $increment_ratio;
			$margin_limit = $max_path_deviation + $min_beam_margin;
			$search_deviation = $margin_limit if $margin_limit > $search_deviation;

			++$iteration;

			say "Iteration $iteration with search deviation $search_deviation";
			say "";

			undef %forward_log_prob;
			$forward_log_prob{0}{0} = 0;

			$old_backtrace = $backtrace;
			undef $backtrace;

			$forward_prob_cnt = 1;
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

                $length_neg_log_prob_pos_1_minus_1 = $length_neg_log_prob_1{$length_pos_1_minus_1};

                $length_pair_1 = $length_pos_1_minus_1 + $length_pos_1_minus_2;
                $length_neg_log_prob_pos_1_minus_2 = $length_neg_log_prob_1{$length_pos_1_minus_2};

				for $pos_2 ($lower_limit..$upper_limit) {
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

						unless (defined $best_score and $new_score < $best_score) {
							$best_score = $new_score;
							$best_bead_score = $new_bead_score;
							$best_bead = 'delete';
						}
					}

                    if (defined($forward_log_prob = $forward_log_prob{$pos_1}{$pos_2_minus_1})) {
						$new_bead_score = $insert_score_base + $length_neg_log_prob_2{$length_pos_2_minus_1};
						$new_score = $new_bead_score - $forward_log_prob;

						push(@forward_log_probs, -$new_score);

						unless (defined $best_score and $new_score < $best_score) {
							$best_score = $new_score;
							$best_bead_score = $new_bead_score;
							$best_bead = 'insert';
						}
					}

                    if (defined($forward_log_prob = $forward_log_prob{$pos_1_minus_1}{$pos_2_minus_1})) {
						$new_bead_score = $match_score_base +
							$length_neg_log_prob_pos_1_minus_1 +
							length_neg_log_cond_prob_2($length_pos_1_minus_1, $length_pos_2_minus_1);
						$new_score = $new_bead_score - $forward_log_prob;

						push(@forward_log_probs, -$new_score);

						unless (defined $best_score and $new_score < $best_score) {
							$best_score = $new_score;
							$best_bead_score = $new_bead_score;
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

						unless (defined $best_score and $new_score < $best_score) {
							$best_score = $new_score;
							$best_bead_score = $new_bead_score;
							$best_bead = 'contract';
						}
					}

                    if (defined($forward_log_prob = $forward_log_prob{$pos_1_minus_1}{$pos_2_minus_2})) {
                        unless (defined $target_pair_2_neg_log_prob{$length_pos_2_minus_2}{$length_pos_2_minus_1}) {
							warn "ERROR: no normalization for expand pair\n";
                            exit(1);
						}

						$new_bead_score = $expand_score_base +
							$length_neg_log_prob_1{$length_pos_1_minus_1} +
							$target_pair_2_neg_log_prob{$length_pos_2_minus_2}{$length_pos_2_minus_1} +
							length_neg_log_cond_prob_2($length_pos_1_minus_1,
                                $length_pos_2_minus_1 + $length_pos_2_minus_2);
						$new_score = $new_bead_score - $forward_log_prob;

						push(@forward_log_probs, -$new_score);

						unless (defined $best_score and $new_score < $best_score) {
							$best_score = $new_score;
							$best_bead_score = $new_bead_score;
							$best_bead = 'expand';
						}
					}

					if (defined $best_score) {
						$forward_log_prob{$pos_1}{$pos_2} = log_add_list(@forward_log_probs);
						++$forward_prob_cnt;
						$backtrace->{$pos_1}{$pos_2} = $best_bead;
					}
				}

				++$pos_1;
				++$print_ctr;
			}

			--$pos_1;
			say "\rposition $pos_1, $lower_limit-$upper_limit";

			$total_observation_log_prob = $forward_log_prob{$sent_cnt_1}{$sent_cnt_2 };

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
			$pos_1 = $sent_cnt_1 ;
			$pos_2 = $sent_cnt_2;
			$alignment_diffs = 0;

			until ($pos_1 == 0 and $pos_2 == 0) {
				$deviation = abs(int(($sent_cnt_ratio * $pos_1) + 0.000001) - $pos_2);
				$max_path_deviation = $deviation if $deviation > $max_path_deviation;

				$bead = $backtrace->{$pos_1}{$pos_2};

				++$alignment_diffs if defined $old_backtrace->{$pos_1}{$pos_2} and $bead ne $old_backtrace->{$pos_1}{$pos_2};
				++$bead_type_cnt{$bead} if $bead;
				++$total_bead_cnt if $bead;

				if ($bead eq 'match') {
					--$pos_1;
					--$pos_2;
				}
				elsif ($bead eq 'contract') {
					$pos_1 -= 2;
					--$pos_2;
				}
				elsif ($bead eq 'expand') {
					--$pos_1;
					$pos_2 -= 2;
				}
				elsif ($bead eq 'delete') {
					--$pos_1;
				}
				elsif ($bead eq 'insert') {
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
		}

	# Backward pass

		say "";
		say "Backward pass of forward-backward algorithm";
		say "";

		undef %bead_type_cnt;
		undef %length_backward_log_prob;
		$total_bead_cnt = 0;
		$high_prob_match_cnt = 0;
		$length_backward_log_prob{$sent_cnt_1}{$sent_cnt_2} = 0;
		$backward_prob_cnt = 1;
		$saved_backward_prob_cnt = 1;
		$pos_1 =  $sent_cnt_1 + 1;
		$print_ctr = 0;

		while ($pos_1 > 0) {
			--$pos_1;
			$diagonal_pos = int(($sent_cnt_ratio * $pos_1) + 0.000001);

			$lower_limit = int($diagonal_pos - $search_deviation);
			$lower_limit = 0 if $lower_limit < 0;

			$upper_limit = int($diagonal_pos + $search_deviation);
			$upper_limit = $sent_cnt_2 if $upper_limit > $sent_cnt_2;

			if ($print_ctr == 100) {
				print "\rposition $pos_1, $lower_limit-$upper_limit         ";
				$print_ctr = 0;
			}

			++$print_ctr;

            $pos_1_plus_1 = $pos_1 + 1;
            $pos_1_plus_2 = $pos_1 + 2;

            $length_pos_1 = $sent_length_1{$pos_1};
            $length_pos_1_plus_1 = $sent_length_1{$pos_1_plus_1} // 0;

            $length_pair_1 = $length_pos_1 + $length_pos_1_plus_1;

			for $pos_2 (reverse $lower_limit..$upper_limit) {
				$pos_2_plus_1 = $pos_2 + 1;
				$pos_2_plus_2 = $pos_2 + 2;

                $length_pos_2 = $sent_length_2{$pos_2};
                $length_pos_2_plus_1 = $sent_length_2{$pos_2_plus_1};

				$norm_forward_log_prob = $forward_log_prob{$pos_1}{$pos_2} - $total_observation_log_prob;

				undef @length_backward_log_probs;
				$backtrace_cnt = 0;

                if (defined($length_backward_log_prob = $length_backward_log_prob{$pos_1_plus_1}{$pos_2})) {
					$new_bead_score = $delete_score_base + $length_neg_log_prob_1{$length_pos_1};
					$bead_length_backward_log_prob = $length_backward_log_prob - $new_bead_score;
					$bead_total_log_prob = $bead_length_backward_log_prob + $norm_forward_log_prob;

					if ($bead_total_log_prob > $log_one_half) {
						++$backtrace_cnt;
						++$bead_type_cnt{'delete'};
						++$total_bead_cnt;
					}

					push(@length_backward_log_probs, $bead_length_backward_log_prob);
				}

                if (defined($length_backward_log_prob = $length_backward_log_prob{$pos_1}{$pos_2_plus_1})) {
					$new_bead_score = $insert_score_base + $length_neg_log_prob_2{$length_pos_2};
					$bead_length_backward_log_prob = $length_backward_log_prob - $new_bead_score;
					$bead_total_log_prob = $bead_length_backward_log_prob + $norm_forward_log_prob;

					if ($bead_total_log_prob > $log_one_half) {
						++$backtrace_cnt;
						++$bead_type_cnt{'insert'};
						++$total_bead_cnt;
					}

					push(@length_backward_log_probs, $bead_length_backward_log_prob);
				}

                if (defined($length_backward_log_prob = $length_backward_log_prob{$pos_1_plus_1}{$pos_2_plus_1})) {
					$new_bead_score = $match_score_base +
						$length_neg_log_prob_1{$length_pos_1} +
						length_neg_log_cond_prob_2($length_pos_1, $length_pos_2);
					$bead_length_backward_log_prob = $length_backward_log_prob - $new_bead_score;
					$bead_total_log_prob = $bead_length_backward_log_prob + $norm_forward_log_prob;

					if ($bead_total_log_prob > $log_one_half) {
						++$backtrace_cnt;
						++$bead_type_cnt{'match'};
						++$total_bead_cnt;
						++$high_prob_match_cnt if $bead_total_log_prob > $log_high_prob_threshold;
					}

					push(@length_backward_log_probs, $bead_length_backward_log_prob);
				}

                if (defined($length_backward_log_prob = $length_backward_log_prob{$pos_1_plus_2}{$pos_2_plus_1})) {
					$new_bead_score = $contract_score_base +
						$length_neg_log_prob_1{$length_pos_1} +
						$length_neg_log_prob_1{$length_pos_1_plus_1} +
						length_neg_log_cond_prob_2($length_pair_1, $length_pos_2);
					$bead_length_backward_log_prob = $length_backward_log_prob - $new_bead_score;
					$bead_total_log_prob = $bead_length_backward_log_prob + $norm_forward_log_prob;

					if ($bead_total_log_prob > $log_one_half) {
						++$backtrace_cnt;
						++$bead_type_cnt{'contract'};
						++$total_bead_cnt;
					}

					push(@length_backward_log_probs, $bead_length_backward_log_prob);
				}

                if (defined($length_backward_log_prob = $length_backward_log_prob{$pos_1_plus_1}{$pos_2_plus_2})) {
					$new_bead_score = $expand_score_base +
						$length_neg_log_prob_1{$length_pos_1} +
						$target_pair_2_neg_log_prob{$length_pos_2}{$length_pos_2_plus_1} +
						length_neg_log_cond_prob_2($length_pos_1, $length_pos_2 + $length_pos_2_plus_1);
					$bead_length_backward_log_prob = $length_backward_log_prob - $new_bead_score;
					$bead_total_log_prob = $bead_length_backward_log_prob + $norm_forward_log_prob;

					if ($bead_total_log_prob > $log_one_half) {
						++$backtrace_cnt;
						++$bead_type_cnt{'expand'};
						++$total_bead_cnt;
					}

					push(@length_backward_log_probs, $bead_length_backward_log_prob);
				}

				if ($backtrace_cnt > 1) {
					warn "\nERROR: more than one backtrace bead at $pos_1, $pos_2 ($sent_file_1, $sent_file_2)\n";
					next;
				}

				if (@length_backward_log_probs) {
					++$backward_prob_cnt;
					$length_backward_log_prob = log_add_list(@length_backward_log_probs);

					if (($length_backward_log_prob + $norm_forward_log_prob) > $conf_threshold) {
						++$saved_backward_prob_cnt;
						$length_backward_log_prob{$pos_1}{$pos_2} = $length_backward_log_prob;
					}
				}
			}
		}

		say "\rposition $pos_1, $lower_limit-$upper_limit         ";
		say "Backward probs computed: $backward_prob_cnt";
		say "Backward probs saved: $saved_backward_prob_cnt";
		say "End to end backward score: $length_backward_log_prob{0}{0}";
		say "";
		say "$total_bead_cnt total beads:";
		say "  $count $bead" while ($bead, $count) = each %bead_type_cnt;
		say "$high_prob_match_cnt high prob matches";

		$intermed_time_3 = (times)[0];
		$pass_time = $intermed_time_3 - $intermed_time_2;
		say "$pass_time seconds backward pass time";
	}

	say "";
	say "ALIGNING SENTENCES BY LENGTH AND WORD ASSOCIATION";

	$bead_type_total_score = 0;
	$iteration = 1;

	while ($iteration) {
		$intermed_time_3 = (times)[0];

		say "";
		say "Forward pass of forward-backward algorithm";
		say $iterate_flag ? "Iteration $iteration\n" : "";

		undef %forward_log_prob;
		$forward_log_prob{0}{0} = 0;
		$forward_prob_cnt = 1;
		$pos_1 = 0;
		$print_ctr = 0;

		while ($pos_1 <= $sent_cnt_1) {
			if ($print_ctr == 100) {
				print "\rposition $pos_1";
				$print_ctr = 0;
			}

			$pos_1_minus_1 = $pos_1 - 1;
			$pos_1_minus_2 = $pos_1 - 2;

            $length_pos_1_minus_1 = $sent_length_1{$pos_1_minus_1} // 0;
			$length_pos_1_minus_2 = $sent_length_1{$pos_1_minus_2} // 0;

            $length_pair_1 = $length_pos_1_minus_1 + $length_pos_1_minus_2;

            $words_pos_1_minus_1 = $words_1{$pos_1_minus_1};
            $words_pos_1_minus_2 = $words_1{$pos_1_minus_2};
            $word_seq_score_pos_1_minus_1 = word_seq_score(\%token_score_1, $words_pos_1_minus_1);

            $length_neg_log_prob_pos_1_minus_1 = $length_neg_log_prob_1{$length_pos_1_minus_1};
            $length_neg_log_prob_pos_1_minus_2 = $length_neg_log_prob_1{$length_pos_1_minus_2};

            if ($length_pos_1_minus_1 > 0 and $length_pos_1_minus_2 > 0) {
                $words_pair_1 = [@{$words_pos_1_minus_2}, @{$words_pos_1_minus_1}];
            }

            $word_seq_score_pos_1_minus_2 = word_seq_score(\%token_score_1, $words_pos_1_minus_2);

			foreach $pos_2 (sort {$a <=> $b} keys %{$length_backward_log_prob{$pos_1}}) {
				$pos_2_minus_1 = $pos_2 - 1;
				$pos_2_minus_2 = $pos_2 - 2;

				$length_pos_2_minus_1 = $sent_length_2{$pos_2_minus_1};
				$length_pos_2_minus_2 = $sent_length_2{$pos_2_minus_2};

                $words_pos_2_minus_1 = $words_2{$pos_2_minus_1};
				$words_pos_2_minus_2 = $words_2{$pos_2_minus_2};

                undef @forward_log_probs;

                if (defined($forward_log_prob = $forward_log_prob{$pos_1_minus_1}{$pos_2})) {
                    unless (defined($new_bead_score = $bead_score{$pos_1}{$pos_2}{'delete'})) {
						$new_bead_score =
							$word_seq_score_pos_1_minus_1 +
							$length_neg_log_prob_pos_1_minus_1;
						$bead_score{$pos_1}{$pos_2}{'delete'} = $new_bead_score;
					}
					
					push(@forward_log_probs, $forward_log_prob - $new_bead_score - $delete_score_base);
				}

                if (defined($forward_log_prob = $forward_log_prob{$pos_1}{$pos_2_minus_1})) {
                    unless (defined($new_bead_score = $bead_score{$pos_1}{$pos_2}{'insert'})) {
						$new_bead_score =
							word_seq_score(\%token_score_2, $words_pos_2_minus_1) +
							$length_neg_log_prob_2{$length_pos_2_minus_1};
						$bead_score{$pos_1}{$pos_2}{'insert'} = $new_bead_score;
					}

					push(@forward_log_probs, $forward_log_prob - $new_bead_score - $insert_score_base);
				}

                if (defined($forward_log_prob = $forward_log_prob{$pos_1_minus_1}{$pos_2_minus_1})) {
                    unless (defined($new_bead_score = $bead_score{$pos_1}{$pos_2}{'match'})) {
						$new_bead_score =
							$word_seq_score_pos_1_minus_1 +
							$length_neg_log_prob_pos_1_minus_1 +
							word_seq_trans_score($words_pos_1_minus_1, $words_pos_2_minus_1) +
                                length_neg_log_cond_prob_2($length_pos_1_minus_1, $length_pos_2_minus_1);
						$bead_score{$pos_1}{$pos_2}{'match'} = $new_bead_score;
					}

					push(@forward_log_probs, $forward_log_prob - $new_bead_score - $match_score_base);
				}

                if (defined($forward_log_prob = $forward_log_prob{$pos_1_minus_2}{$pos_2_minus_1})) {
                    unless (defined($new_bead_score = $bead_score{$pos_1}{$pos_2}{'contract'})) {
						$new_bead_score =
							$word_seq_score_pos_1_minus_1 +
							$length_neg_log_prob_pos_1_minus_1 +
							$word_seq_score_pos_1_minus_2 +
							$length_neg_log_prob_pos_1_minus_2 +
							word_seq_trans_score($words_pair_1, $words_pos_2_minus_1) +
                                length_neg_log_cond_prob_2($length_pair_1, $length_pos_2_minus_1);
						$bead_score{$pos_1}{$pos_2}{'contract'} = $new_bead_score;
					}
					
					push(@forward_log_probs, $forward_log_prob - $new_bead_score - $contract_score_base);
				}

                if (defined($forward_log_prob = $forward_log_prob{$pos_1_minus_1}{$pos_2_minus_2})) {
					unless (defined $target_pair_2_neg_log_prob{$length_pos_2_minus_2}{$length_pos_2_minus_1}) {
						warn "ERROR: no normalization for expand pair\n";
					}

                    unless (defined($new_bead_score = $bead_score{$pos_1}{$pos_2}{'expand'})) {
						$new_bead_score =
							$word_seq_score_pos_1_minus_1 +
							$length_neg_log_prob_1{$length_pos_1_minus_1} +
							$target_pair_2_neg_log_prob{$length_pos_2_minus_2}{$length_pos_2_minus_1} +
							word_seq_trans_score($words_pos_1_minus_1,
                                [@{$words_pos_2_minus_2}, @{$words_pos_2_minus_1}]) +
							length_neg_log_cond_prob_2($length_pos_1_minus_1,
                                $length_pos_2_minus_1 + $length_pos_2_minus_2);
						$bead_score{$pos_1}{$pos_2}{'expand'} = $new_bead_score;
					}

					push(@forward_log_probs, $forward_log_prob - $new_bead_score - $expand_score_base);
				}

				if (@forward_log_probs) {
					$forward_log_prob{$pos_1}{$pos_2} = log_add_list(@forward_log_probs);
					++$forward_prob_cnt;
				}
			}

			++$pos_1;
			++$print_ctr;
		}

		$total_observation_log_prob = $forward_log_prob{$sent_cnt_1}{$sent_cnt_2};

		--$pos_1;
		say "\rposition $pos_1";
		say "Forward probs computed: $forward_prob_cnt";
		say "End to end forward score: $total_observation_log_prob";

		$intermed_time_4 = (times)[0];
		$pass_time = $intermed_time_4 - $intermed_time_3;
		say "$pass_time seconds forward pass time";

	# Backward pass

		say "";
		say "Backward pass of forward-backward algorithm";
		say "";

		undef @backtrace_list;
		undef %bead_type_cnt;
		$total_bead_cnt = 0;
		$high_prob_match_cnt = 0;
		$backward_prob_cnt = 1;
		$saved_backward_prob_cnt = 1;
		undef %backward_log_prob;
		$backward_log_prob{$sent_cnt_1}{$sent_cnt_2} = 0;
		$pos_1 = $sent_cnt_1 + 1;
		$print_ctr = 0;

		while ($pos_1 > 0) {
			--$pos_1;

			if ($print_ctr == 100) {
				print "\rposition $pos_1       ";
				$print_ctr = 0;
			}

			++$print_ctr;
			
			$pos_1_plus_1 = $pos_1 + 1;
			$pos_1_plus_2 = $pos_1 + 2;

			foreach $pos_2 (sort {$b <=> $a} keys %{$forward_log_prob{$pos_1}}) {
				$norm_forward_log_prob = $forward_log_prob{$pos_1}{$pos_2} - $total_observation_log_prob;
                $pos_2_plus_1 = $pos_2 + 1;
				$pos_2_plus_2 = $pos_2 + 2;

				$backtrace_cnt = 0;
				undef @backward_log_probs;

                if (defined($backward_log_prob = $backward_log_prob{$pos_1_plus_1}{$pos_2})) {
					$bead_backward_log_prob = $backward_log_prob - $delete_score_base - $bead_score{$pos_1_plus_1}{$pos_2}{'delete'};
					$bead_total_prob = exp($bead_backward_log_prob + $norm_forward_log_prob);

					if ($bead_total_prob > 0.5) {
						push(@backtrace_list, [$pos_1, $pos_2, 'delete', $bead_total_prob]);
						++$backtrace_cnt;
					}

					$bead_type_cnt{'delete'} += $bead_total_prob;
					$total_bead_cnt += $bead_total_prob;
					push(@backward_log_probs, $bead_backward_log_prob);
				}

                if (defined($backward_log_prob = $backward_log_prob{$pos_1}{$pos_2_plus_1})) {
					$bead_backward_log_prob = $backward_log_prob - $insert_score_base - $bead_score{$pos_1}{$pos_2_plus_1}{'insert'};
					$bead_total_prob = exp($bead_backward_log_prob + $norm_forward_log_prob);

					if ($bead_total_prob > 0.5) {
						push(@backtrace_list, [$pos_1, $pos_2, 'insert', $bead_total_prob]);
						++$backtrace_cnt;
					}

					$bead_type_cnt{'insert'} += $bead_total_prob;
					$total_bead_cnt += $bead_total_prob;
					push(@backward_log_probs, $bead_backward_log_prob);
				}

                if (defined($backward_log_prob = $backward_log_prob{$pos_1_plus_1}{$pos_2_plus_1})) {
					$bead_backward_log_prob = $backward_log_prob - $match_score_base - $bead_score{$pos_1_plus_1}{$pos_2_plus_1}{'match'};
					$bead_total_prob = exp($bead_backward_log_prob + $norm_forward_log_prob);

					if ($bead_total_prob > 0.5) {
						push(@backtrace_list, [$pos_1, $pos_2, 'match', $bead_total_prob]);
						++$backtrace_cnt;

						if ($bead_total_prob > $high_prob_threshold) {
							++$high_prob_match_cnt;
						}
					}

					$bead_type_cnt{'match'} += $bead_total_prob;
					$total_bead_cnt += $bead_total_prob;
					push(@backward_log_probs, $bead_backward_log_prob);
				}

                if (defined($backward_log_prob = $backward_log_prob{$pos_1_plus_2}{$pos_2_plus_1})) {
					$bead_backward_log_prob = $backward_log_prob - $contract_score_base - $bead_score{$pos_1_plus_2}{$pos_2_plus_1}{'contract'};
					$bead_total_prob = exp($bead_backward_log_prob + $norm_forward_log_prob);

					if ($bead_total_prob > 0.5) {
						push(@backtrace_list, [$pos_1, $pos_2, 'contract', $bead_total_prob]);
						++$backtrace_cnt;
					}

					$bead_type_cnt{'contract'} += $bead_total_prob;
					$total_bead_cnt += $bead_total_prob;
					push(@backward_log_probs, $bead_backward_log_prob);
				}

                if (defined($backward_log_prob = $backward_log_prob{$pos_1_plus_1}{$pos_2_plus_2})) {
					$bead_backward_log_prob = $backward_log_prob - $expand_score_base - $bead_score{$pos_1_plus_1}{$pos_2_plus_2}{'expand'};
					$bead_total_prob = exp($bead_backward_log_prob + $norm_forward_log_prob);

					if ($bead_total_prob > 0.5) {
						push(@backtrace_list, [$pos_1, $pos_2, 'expand', $bead_total_prob]);
						++$backtrace_cnt;
					}

					$bead_type_cnt{'expand'} += $bead_total_prob;
					$total_bead_cnt += $bead_total_prob;
					push(@backward_log_probs, $bead_backward_log_prob);
				}

				if ($backtrace_cnt > 1) {
					warn "\nERROR: more than one backtrace bead at $pos_1, $pos_2 ($sent_file_1, $sent_file_2)\n";
					next;
				}

				if (@backward_log_probs) {
					++$backward_prob_cnt;
					$backward_log_prob = log_add_list(@backward_log_probs);

					if (($backward_log_prob + $norm_forward_log_prob) > $conf_threshold) {
						++$saved_backward_prob_cnt;
						$backward_log_prob{$pos_1}{$pos_2} = $backward_log_prob;
					}
				}
			}
		}

		$backward_log_prob{0}{0} //= 0;

		say "\rposition $pos_1        ";
		say "Backward probs computed: $backward_prob_cnt";
		say "Backward probs saved: $saved_backward_prob_cnt";
		say "End to end backward score: $backward_log_prob{0}{0}" ;
		say "";
		say "$total_bead_cnt total beads:";
		say "  $count $bead" while ($bead, $count) = each %bead_type_cnt;
		say "$high_prob_match_cnt high prob matches";

		if ($iterate_flag) {
			if ($smooth_flag) {
				$total_bead_cnt += 1000;
				$match_score_base = -log(($bead_type_cnt{'match'} + 940) / $total_bead_cnt);        # 1-1
				$contract_score_base = -log(($bead_type_cnt{'contract'} + 20) / $total_bead_cnt);   # 2-1
				$expand_score_base = -log(($bead_type_cnt{'expand'} + 20) / $total_bead_cnt);       # 1-2
				$delete_score_base = -log(($bead_type_cnt{'delete'} + 10) / $total_bead_cnt);       # 1-0
				$insert_score_base = -log(($bead_type_cnt{'insert'} + 10) / $total_bead_cnt);       # 0-1
			}
			else {
				foreach $bead_type (keys %bead_type_cnt) {
					$bead_type_cnt{$bead_type} += $conf_threshold_prob;
					$total_bead_cnt += $conf_threshold_prob;
				}

				$match_score_base = -log($bead_type_cnt{'match'} / $total_bead_cnt);         # 1-1
				$contract_score_base = -log($bead_type_cnt{'contract'} / $total_bead_cnt);   # 2-1
				$expand_score_base = -log($bead_type_cnt{'expand'} / $total_bead_cnt);       # 1-2
				$delete_score_base = -log($bead_type_cnt{'delete'} / $total_bead_cnt);       # 1-0
				$insert_score_base = -log($bead_type_cnt{'insert'} / $total_bead_cnt);       # 0-1
			}

			$old_bead_type_total_score = $bead_type_total_score;
			$bead_type_total_score =
				($match_score_base * $bead_type_cnt{'match'}) +
				($contract_score_base * $bead_type_cnt{'match'}) +
				($expand_score_base * $bead_type_cnt{'match'}) +
				($delete_score_base * $bead_type_cnt{'match'}) +
				($insert_score_base * $bead_type_cnt{'match'});

			say "Total bead type score: $bead_type_total_score";

			if (abs(($old_bead_type_total_score - $bead_type_total_score) /
				$bead_type_total_score) > $bead_type_diff_threshold) {
				++$iteration;
			}
			else {
				$iteration = 0;
			}
		}
		else {
			$iteration = 0;
		}

		$intermed_time_5 = (times)[0];
		$pass_time = $intermed_time_5 - $intermed_time_4;
		say "$pass_time seconds backward pass time";

	}

	open($out, ">:encoding(UTF-8)", "$sent_file_1.$sent_file_2.backtrace") or die "Failed to create '$sent_file_1.$sent_file_2.backtrace'!\n$!";

	while (@backtrace_list) {
		($pos_1, $pos_2, $bead, $prob) = @{pop(@backtrace_list)};
		next unless defined $pos_1 and defined $pos_2 and defined $bead and defined $prob and $prob =~ /^\d{1,10}[.,]\d+$/;
		printf $out "%6d %6d %-8s %10.8f\n", $pos_1, $pos_2, $bead, $prob;
	}

	close($out);

	$final_time = (times)[0];
	$total_time = $final_time - $start_time;
	say "";
	say "$total_time seconds total time";
	say "";
	say "========================================================";
}

close($sents);

# ==============================================================================
sub length_neg_log_cond_prob_2 {
	my ($length1, $length2) = @_;

	unless (defined $cache{$length1}{$length2}) {
		my $mean = $length1 * $mean_bead_length_ratio;
		fill_in_missing_neg_log_probs($length1, $length2, $mean, log($mean))
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


sub word_seq_trans_score {
	my ($ref_1, $ref_2) = @_;
	my ($tok_1, $tok_2, $trans_prob_sum);
	my $cur_score_sum = -log(1 / (@{$ref_1} + 1)) * @{$ref_2};  # normalizes over all possible alignment patterns

	foreach $tok_2 (@{$ref_2}) {
		$trans_prob_sum = 0;

		foreach $tok_1 ('(empty)', @{$ref_1}) {
			next unless defined $trans_prob{$tok_1}{$tok_2};
			$trans_prob_sum += $trans_prob{$tok_1}{$tok_2};
		}

		$cur_score_sum -= log($trans_prob_sum) if $trans_prob_sum > 0;
	}

	return $cur_score_sum;
}


sub word_seq_score {
    my ($cur_score_sum, $tok);
    my ($ref_token_score, $ref_tokens) = @_;

    foreach $tok (@{$ref_tokens}) {
        next unless defined $ref_token_score->{$tok};
        $cur_score_sum += $ref_token_score->{$tok};
    }

    return $cur_score_sum;
}
