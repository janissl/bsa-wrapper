#!/usr/bin/env perl

# (c) Microsoft Corporation. All rights reserved.

# Builds IBM model 1, word alignment model, to be used in sentence
# alignment.

use strict;
use warnings;
use 5.014;


my ($sent_file_1, $sent_file_2) = @ARGV;

my $min_corpus_coverage = 0.9;

my (%token_1_cnt, %token_2_cnt);
my ($line, $token, @tokens, $count, $prob);

my $start_time = (times)[0];
my $total_count = 0;
my $sent_cnt_1 = 0;
my $sent_cnt_2 = 0;

open(my $in1, "<:encoding(UTF-8)", "$sent_file_1.words") ||
	die("cannot open data file $sent_file_1.words\n");

while ($line = <$in1>) {
	++$sent_cnt_1;
	@tokens = split(' ', $line);

	foreach $token (@tokens) {
		++$token_1_cnt{$token};
		++$total_count;
	}
}

close($in1);

my $total_type_count = keys(%token_1_cnt);
my $high_prob_type_count = 0;
my $token_count = 0;
my $prev_count = 0;
my $cumulative_count = 0;
my $cumulative_freq = 0;

foreach $token (sort {$token_1_cnt{$b} <=> $token_1_cnt{$a}} keys(%token_1_cnt)) {
	$prev_count = $token_count;
	$token_count = $token_1_cnt{$token};

	last if ($cumulative_freq >= $min_corpus_coverage and $token_count < $prev_count) or $token_count == 1;

	++$high_prob_type_count;
	$cumulative_count += $token_count;
	$cumulative_freq = $cumulative_count / $total_count;
}

say "";
say "Using $high_prob_type_count tokens out of $total_type_count from $sent_file_1 with $prev_count or more occurrences, representing $cumulative_freq of corpus";

my $count_limit_1 = $prev_count;
my $other_count = 0;

while (($token, $count) = each %token_1_cnt) {
	if ($count < $count_limit_1) {
		$other_count += $count;
		delete($token_1_cnt{$token});
	}
}

$token_1_cnt{'(other)'} = $other_count;
$total_count = 0;

open(my $in2, "<:encoding(UTF-8)", "$sent_file_2.words") or
	die("cannot open data file $sent_file_2.words\n");

while ($line = <$in2>) {
	++$sent_cnt_2;
	@tokens = split(' ', $line);

	foreach $token (@tokens) {
		++$token_2_cnt{$token};
		++$total_count;
	}
}

close($in2);

unless ($sent_cnt_1 == $sent_cnt_2) {
	die("ERROR: $sent_cnt_1 sentences in $sent_file_1.words and $sent_cnt_2 sentences in $sent_file_2.words\n");
}

$total_type_count = keys(%token_2_cnt);
$high_prob_type_count = 0;
$token_count = 0;
$prev_count = 0;
$cumulative_count = 0;
$cumulative_freq = 0;

foreach $token (sort {$token_2_cnt{$b} <=> $token_2_cnt{$a}} keys(%token_2_cnt)) {
	$prev_count = $token_count;
	$token_count = $token_2_cnt{$token};

	last if ($cumulative_freq >= $min_corpus_coverage and $token_count < $prev_count) or $token_count == 1;

	++$high_prob_type_count;
	$cumulative_count += $token_count;
	$cumulative_freq = $cumulative_count / $total_count;
};

say "";
say "Using $high_prob_type_count tokens out of $total_type_count from $sent_file_2 with $prev_count or more occurrences, representing $cumulative_freq of corpus";
say "";

my $count_limit_2 = $prev_count;
$other_count = 0;

while (($token, $count) = each %token_2_cnt) {
	if ($count < $count_limit_2) {
		$other_count += $count;
		delete($token_2_cnt{$token});
	}
}

$token_2_cnt{'(other)'} = $other_count;

my (%trans_count, %trans_count_sum);
my ($line_1, $line_2, $token_1, $token_2, @tokens_1, @tokens_2, $fract_count);
my $sent_ctr = 0;
my $print_ctr = 0;

open(my $inw1, "<:encoding(UTF-8)", "$sent_file_1.words") or die "Failed to read '$sent_file_1.words'!\n$!";
open(my $inw2, "<:encoding(UTF-8)", "$sent_file_2.words") or die "Failed to read '$sent_file_2.words'!\n$!";
open(my $train1, ">:encoding(UTF-8)", "$sent_file_1.words.train") or die "Failed to create '$sent_file_1.words.train'!\n$!";
open(my $train2, ">:encoding(UTF-8)", "$sent_file_2.words.train") or die "Failed to create '$sent_file_2.words.train'!\n$!";

say "Initial Iteration";

while (defined($line_1 = <$inw1>) and defined($line_2 = <$inw2>)) {
	++$sent_ctr;
	++$print_ctr;

	if ($print_ctr == 100) {
		print "\r$sent_ctr sentence pairs";
		$print_ctr = 0;
	}

	@tokens_1 = split(' ', $line_1);

	foreach $token (@tokens_1) {
		$token = '(other)' unless exists($token_1_cnt{$token});
	}

	push(@tokens_1, '(empty)');

	@tokens_2 = split(' ', $line_2);

	foreach $token (@tokens_2) {
		$token = '(other)' unless exists($token_2_cnt{$token});
	}

	say $train1 "@tokens_1";
	say $train2 "@tokens_2";

	$fract_count = 1 / @tokens_1;

	foreach $token_2 (@tokens_2) {
		foreach $token_1 (@tokens_1) {
			$trans_count{$token_1}{$token_2} += $fract_count;
			$trans_count_sum{$token_1} += $fract_count;
		}
	}
}

close($train2);
close($train1);
close($inw2);
close($inw1);

say "\r$sent_ctr sentence pairs";

my $trans_prob = {};
my ($ref, $count_sum);
my $num_probs = 0;

while (($token_1, $ref) = each %trans_count) {
	$count_sum = $trans_count_sum{$token_1};

	while (($token_2, $count) = each %{$ref}) {
		$trans_prob->{$token_1}{$token_2} = $count / $count_sum;
		++$num_probs;
	}
}

say "$num_probs probabilities in model";
say "";

my ($inw1tr, $inw2tr, $score_sum, $fract_count_limit, $trans_prob_sum);
my $iteration_count = 0;
my $prev_score_sum = 0;

while (1) {
	++$iteration_count;

	say "EM Iteration $iteration_count";

	undef %trans_count;
	undef %trans_count_sum;
	$sent_ctr = 0;
	$print_ctr = 0;
	$score_sum = 0;

	open($inw1tr, "<:encoding(UTF-8)", "$sent_file_1.words.train") or die "Failed to read '$sent_file_1.words.train'!\n$!";
	open($inw2tr, "<:encoding(UTF-8)", "$sent_file_2.words.train") or die "Failed to read '$sent_file_2.words.train'!\n$!";

	while (defined($line_1 = <$inw1tr>) and defined($line_2 = <$inw2tr>)) {
		++$sent_ctr;
		++$print_ctr;

		@tokens_1 = split(' ', $line_1);
		@tokens_2 = split(' ', $line_2);

		$fract_count_limit = 1 / @tokens_1;

		foreach $token_2 (@tokens_2) {
			$trans_prob_sum = 0;

			foreach $token_1 (@tokens_1) {
				next unless defined $trans_prob->{$token_1}{$token_2};
				$trans_prob_sum += $trans_prob->{$token_1}{$token_2};
			}

			$score_sum -= log($trans_prob_sum);

			foreach $token_1 (@tokens_1) {
				next unless defined $trans_prob->{$token_1}{$token_2};
				$fract_count = $trans_prob->{$token_1}{$token_2} / $trans_prob_sum;

				if ($fract_count > $fract_count_limit) {
					$trans_count{$token_1}{$token_2} += $fract_count;
					$trans_count_sum{$token_1} += $fract_count;
				}
				else {
					$trans_count{'(empty)'}{$token_2} += $fract_count;
					$trans_count_sum{'(empty)'} += $fract_count;
				}
			}
		}
	}

	close($inw2tr);
	close($inw1tr);

	say "total training score: $score_sum";
	
	if (abs($prev_score_sum) > 0 && abs($score_sum) >= abs($prev_score_sum)) {
		say "Word translation model converged";
		last;
	}
	
	$prev_score_sum = $score_sum;

	undef $trans_prob;
	$num_probs = 0;

	while (($token_1, $ref) = each %trans_count) {
		$count_sum = $trans_count_sum{$token_1};

		while (($token_2, $count) = each %{$ref}) {
			$trans_prob->{$token_1}{$token_2} = $count / $count_sum;
			++$num_probs;
		}
	}

	say "$num_probs probabilities in model";
	say "";
}

open(my $out, ">:encoding(UTF-8)", "model-one") or die "Failed to create 'model-one'!\n$!";

while (($token_1, $ref) = each %{$trans_prob}) {
	say $out "$prob $token_1 $token_2" while ($token_2, $prob) = each %{$ref};
}

close($out);

my $final_time = (times)[0];
my $total_time = $final_time - $start_time;
say "$total_time seconds total time";
