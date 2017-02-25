#!/usr/bin/env perl

use strict;
use warnings;

my $file = $ARGV[0];
my $testcase = "";
my $error_collect = "";
my $error_print = "";

if (not defined $file) {
  die "Need filename as parameter!\n";
}

open (my $info, $file) or die "Could not open $file: $!";

print "<testsuite name=\"PT MySQL Test\">\n";
while(my $line = <$info>) {
  if ($line =~ /^(t\/\S+).* (\.*) (skipped:) (.*)$/) { print "<testcase name=\"$1\"><skipped/><system-out>Skip reason:<![CDATA[ $4 ]]></system-out></testcase>\n"; }
  elsif ($line =~ /^ok (\d+) - (.*)$/) { print "<testcase name=\"$testcase - test $1\"><system-out>Test description:<![CDATA[ $2 ]]></system-out></testcase>\n"; }
  elsif ($line =~ /^not ok (\d+) - (.*)$/) { print "<testcase name=\"$testcase - test $1\"><failure/><system-out>Test description:<![CDATA[ $2 ]]></system-out><system-err><![CDATA[ $error_print ]]></system-err></testcase>\n"; }
  elsif ($line =~ /^(t\/\S+).* (\.*) $/) { $testcase = "$1"; $error_print = $error_collect; $error_collect = ""; }
  elsif ($line !~ /^ok$/ && $line !~ /^\d+..\d+$/) { $error_collect = $error_collect . $line; }
}
print "</testsuite>\n"
