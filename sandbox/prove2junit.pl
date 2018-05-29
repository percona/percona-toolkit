#!/usr/bin/env perl

use strict;
use warnings;

my $file = $ARGV[0];
my $testcase = "";
my $testsuite = "";
my $error_collect = "";
my $error_print = "";

if (not defined $file) {
  die "Need filename as parameter!\n";
}

open (my $info, $file) or die "Could not open $file: $!";

print "<testsuites name=\"PT-MySQL\">\n";
while(my $line = <$info>) {
  if ($line =~ /^(t\/)(\S+)(\/)(\S+).* (\.*) (skipped:) (.*)$/) { print "<testcase name=\"$4\"><skipped/><system-out>Skip reason:<![CDATA[ $7 ]]></system-out></testcase>\n"; }
  elsif ($line =~ /^ok (\d+) - (.*)$/) { print "<testcase name=\"$testcase - test $1\"><system-out>Test description:<![CDATA[ $2 ]]></system-out></testcase>\n"; }
  elsif ($line =~ /^not ok (\d+) - (.*)$/) { print "<testcase name=\"$testcase - test $1\"><failure/><system-out>Test description:<![CDATA[ $2 ]]></system-out><system-err><![CDATA[ $error_print ]]></system-err></testcase>\n"; }
  elsif ($line =~ /^(t\/)(\S+)(\/)(\S+).* (\.*) $/) {
    if ( "$2" eq "$testsuite" ) {
      $testcase = "$4"; $error_print = $error_collect; $error_collect = "";
    }
    else {
      if ( "$testsuite" ne "" ) { print "</testsuite>\n"; }
      $testsuite = "$2"; $testcase = "$4"; $error_print = $error_collect; $error_collect = ""; print "<testsuite name=\"$testsuite\">\n";
    }
  }
  elsif ($line !~ /^ok$/ && $line !~ /^\d+..\d+$/) { $error_collect = $error_collect . $line; }
}
print "</testsuite>\n</testsuites>\n";
