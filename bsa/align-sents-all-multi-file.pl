#!/usr/bin/env perl

# (c) Microsoft Corporation. All rights reserved.

# This version lets align-sents-length-plus-words-multi-file2.pl
# handle the iteration over the sentence file pairs, so that the word
# translation file only needs to be loaded once.

use strict;
use warnings;
use 5.014; # necessary for supporting Unicode in regexes

use Cwd qw( abs_path );
use File::Basename qw( dirname basename );


my $script_name = basename(abs_path($0));
my ($dir, $slang, $tlang, $threshold) = @ARGV;
unless (defined $dir and -d $dir) { die "USAGE: perl $script_name DIR [SRC_LANG TRG_LANG [THRESHOLD=0.90]]\n" };
# Useful threshold range: 0.5..0.99, recommended value: 0.9
$threshold //= .9;

opendir(my $dirfh, $dir) or die "Could not open directory $dir\n";
my @all_snt_files = grep /\.snt$/, readdir $dirfh;
closedir($dirfh);

my $prog_dir = dirname(abs_path($0));

chdir($dir);

say "program directory: $prog_dir";
say "data directory: $dir";

my %language_tag;

foreach (@all_snt_files) {
	$_ =~ /.*_(.+?)\.snt$/;
	++$language_tag{$1} if defined $1;
}

unless (scalar keys %language_tag == 2) {
	my $lang_string = join(' ', keys %language_tag);
	 die "not exactly two languages in directory: $lang_string\n";
}

my ($lang_1, $lang_2);

if (defined $slang and defined $tlang) {
	$lang_1 = $slang if (exists($language_tag{$slang}));
	$lang_2 = $tlang if (exists($language_tag{$tlang}));
}
else {
	($lang_1, $lang_2) = sort(keys %language_tag);
}

unless (defined $lang_1 and defined $lang_2) {
	die "Could not find source language ($slang) files and/or target language ($tlang) files in the specified directory: $dir!\n" };

say "language pair: $lang_1-$lang_2";

unless ($language_tag{$lang_1} == $language_tag{$lang_2}) {
	die "$language_tag{$lang_1} $lang_1 files, but $language_tag{$lang_2} $lang_2 files\n";
}

my ($fname, $lcode, @sent_file_1_list, @sent_file_2_list);
my $file_index_limit = -1;

foreach (@all_snt_files) {
	($fname, $lcode) = $_ =~ /(.*_)(.+?)\.snt$/;

	next unless defined $fname and defined $lcode;

	if ($lcode eq $lang_1) {
		push(@sent_file_1_list, join('', $fname, $lang_1, '.snt'));
		push(@sent_file_2_list, join('', $fname, $lang_2, '.snt'));
		++$file_index_limit;
	}
}

say "";
say "Finding length-based alignments and filtering initial high-probability aligned sentences";

my ($cmd, @args, $i, $sent_file_1, $sent_file_2);
$cmd= "perl";

for $i (0..$file_index_limit) {
	$sent_file_1 = $sent_file_1_list[$i];
	$sent_file_2 = $sent_file_2_list[$i];

	@args = ("$prog_dir/align-sents-dp-beam7.pl", $sent_file_1, $sent_file_2);
	system($cmd, @args);
	say "";
	say "========================================================";
	say "";

	@args = ("$prog_dir/filter-initial-aligned-sents.pl", $sent_file_1, $sent_file_2, $threshold);
	system($cmd, @args);
	say "";
	say "========================================================";
}

say "";
say "Concatenating length-aligned sentence files";

my $start_time = (times)[0];
my ($in1, $in2, $line);

open(my $out1, ">:encoding(UTF-8)", "all_$lang_1.snt.words") or die "Failed to create 'all_$lang_1.snt.words'!\n$!";

for $i (0..$file_index_limit) {
	$sent_file_1 = $sent_file_1_list[$i];

	open($in1, "<:encoding(UTF-8)", "$sent_file_1.words") or die "Failed to read '$sent_file_1.words'!\n$!";
	print $out1 $line while $line = <$in1>;
	close($in1);
}

close($out1);

open(my $out2, ">:encoding(UTF-8)", "all_$lang_2.snt.words") or die "Failed to create 'all_$lang_2.snt.words'!\n$!";

for $i (0..$file_index_limit) {
	$sent_file_2 = $sent_file_2_list[$i];

	open($in2, "<:encoding(UTF-8)", "$sent_file_2.words") or die "Failed to read '$sent_file_2.words'!\n$!";
	print $out2 $line while $line = <$in2>;
	close($in2);
}

close($out2);

my $end_time = (times)[0];
my $concat_time = $end_time - $start_time;

say "";
say "$concat_time seconds to concatenate files";
say "";
say "========================================================";
say "";
say "Building word association model";

@args = ("$prog_dir/build-model-one-multi-file.pl", "all_$lang_1.snt", "all_$lang_2.snt");
system($cmd, @args);
say "";
say "========================================================";
say "";
say "Finding alignment based on word associations and lengths and filtering final high-probability aligned sentences";

open(my $out, ">:encoding(UTF-8)", "sentence-file-pair-list") or die "Failed to create 'sentence-file-pair-list'!\n$!";

for $i (0..$file_index_limit) {
	say $out "$sent_file_1_list[$i] $sent_file_2_list[$i]";
}

close($out);

@args = ("$prog_dir/align-sents-length-plus-words-multi-file2.pl");
system($cmd, @args);

for $i (0..$file_index_limit) {
	@args = ("$prog_dir/filter-final-aligned-sents.pl", $sent_file_1_list[$i], $sent_file_2_list[$i], $threshold);
	system($cmd, @args);
	say "";
	say "========================================================";
}

say "";
