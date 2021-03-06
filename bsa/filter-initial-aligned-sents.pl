#!/usr/bin/env perl

# (c) Microsoft Corporation. All rights reserved.

use strict;
use warnings;
use 5.014; # necessary for supporting Unicode in regexes

use File::Basename qw( basename );


my ($sent_file_1, $sent_file_2, $threshold) = @ARGV;

my $sent_file_2_mod = basename($sent_file_2);

$threshold //= .99;
my $start_time = (times)[0];

my $peel_regex = '^[^\w\'\x{2019}]+|[^\w\'\x{2019}]+$';

open(my $in1, "<:encoding(UTF-8)", $sent_file_1) or
	die("cannot open data file $sent_file_1\n");

open(my $out1, ">:encoding(UTF-8)", "$sent_file_1.words") or die "Failed to create '$sent_file_1.words'!\n$!";

open(my $in2, "<:encoding(UTF-8)", $sent_file_2) or
	die("cannot open data file $sent_file_2\n");

open(my $out2, ">:encoding(UTF-8)", "$sent_file_2.words") or die "Failed to create '$sent_file_2.words'!\n$!";

open(my $align, "<:encoding(UTF-8)", "$sent_file_1.$sent_file_2_mod.length-backtrace") or
	die("cannot open data file $sent_file_1.$sent_file_2_mod.length-backtrace\n");

my (@words, $line, $word, $bead_line, $bead_pos_1, $bead_pos_2, $bead, $prob);
my $file_1_pos = 0;
my $file_2_pos = 0;
my $matched_line_cnt = 0;

while ($bead_line = <$align>) {
	($bead_pos_1, $bead_pos_2, $bead, $prob) = split(' ', $bead_line);
	next unless defined $bead_pos_1 and defined $bead_pos_2 and defined $bead and defined $prob;

	if ($bead eq 'match' and $prob > $threshold) {
		++$matched_line_cnt;

		undef @words;

		until ($file_1_pos > $bead_pos_1) {
			$line = <$in1>;
			chomp($line);
			@words = grep($_ =~ s/$peel_regex//ug ? $_ : $_, split(/\s+/, $line));
			++$file_1_pos if @words;
		}

		foreach $word (@words) {
            if ($word =~ /\w/u) {
                $word =~ /\W*(\w.*\w|\w)/u;
                $word = lc($1);
            }
			else {
				$word = '(null)' unless $word;
			}
		}

		say $out1 "@words";

		undef @words;

		until ($file_2_pos > $bead_pos_2) {
			$line = <$in2>;
			chomp($line);
			@words = grep($_ =~ s/$peel_regex//ug ? $_ : $_, split(/\s+/, $line));
			++$file_2_pos if @words;
		}

		foreach $word (@words) {
            if ($word =~ /\w/u) {
                $word =~ /\W*(\w.*\w|\w)/u;
                $word = lc($1);
            }
			else {
				$word = '(null)' unless $word;
			}
		}

		say $out2 "@words";
	}
}

close($align);
close($out2);
close($in2);
close($out1);
close($in1);

say "$matched_line_cnt high prob matched lines";

my $final_time = (times)[0];
my $total_time = $final_time - $start_time;
say "$total_time seconds total time";
