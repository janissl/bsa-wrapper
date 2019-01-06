#!/usr/bin/env perl

# (c) Microsoft Corporation. All rights reserved.

use strict;
use warnings;
use 5.014; # necessary for supporting Unicode in regexes

use Cwd qw( abs_path );
use File::Basename qw( dirname );


my ($sent_file_1, $sent_file_2, $threshold) = @ARGV;
# Useful threshold range: 0.5..0.99, recommended value: 0.9
$threshold //= .9;

my $prog_dir = dirname(abs_path($0));

say "";
say "Finding length-based alignment";

my ($cmd, @args);
$cmd = "perl";

@args = ("$prog_dir/align-sents-dp-beam7.pl", $sent_file_1, $sent_file_2);
system($cmd, @args);
say "";
say "========================================================";
say "";
say "Filtering initial high-probability aligned sentences";

@args = ("$prog_dir/filter-initial-aligned-sents.pl", $sent_file_1, $sent_file_2, $threshold);
system($cmd, @args);
say "";
say "========================================================";
say "";
say "Building word association model";

@args = ("$prog_dir/build-model-one6.pl", $sent_file_1, $sent_file_2);
system($cmd, @args);
say "";
say "========================================================";
say "";
say "Finding alignment based on word associations and lengths";

@args = ("$prog_dir/align-sents-length-plus-words3.pl", $sent_file_1, $sent_file_2);
system($cmd, @args);
say "";
say "========================================================";
say "";
say "Filtering final high-probability aligned sentences";

@args = ("$prog_dir/filter-final-aligned-sents.pl", $sent_file_1, $sent_file_2, $threshold);
system($cmd, @args);
say "";
