#!/usr/bin/env perl

use strict;
use warnings;

my $file = $ARGV[0];
my $testcase = "";
my $testsuite = "";
my $error_collect = "";
my $open_error = 0;

if (not defined $file) {
  die "Need filename as parameter!\n";
}

sub close_error {
  if ( $open_error == 1 ) {
    print "$error_collect ]]></system-err></testcase>\n";
    $error_collect=""; $open_error=0;
  }

  return;
}

open (my $info, $file) or die "Could not open $file: $!";

print "<testsuites name=\"PT-MySQL\">\n";
while(my $line = <$info>) {
  if ($line =~ /^(t\/)(\S+)(\/)(\S+).* (\.*) (skipped:) (.*)$/) {
    close_error();
    print "<testcase name=\"$4\"><skipped/><system-out>Skip reason:<![CDATA[ $7 ]]></system-out></testcase>\n";
  }
  elsif ($line =~ /^ok (\d+) - (.*)$/) {
    close_error();
    print "<testcase name=\"$testcase - test $1\"><system-out>Test description:<![CDATA[ $2 ]]></system-out></testcase>\n";
  }
  elsif ($line =~ /^not ok (\d+) - (.*)$/) {
    close_error();
    print "<testcase name=\"$testcase - test $1\"><failure/><system-out>Test description:<![CDATA[ $2 ]]></system-out><system-err><![CDATA[ ";
    $open_error=1;
  }
  elsif ($line =~ /^(t\/)(\S+)(\/)(\S+).* (\.*) $/) {
    close_error();
    if ( "$2" eq "$testsuite" ) {
      $testcase="$4"; $error_collect="";
    }
    else {
      if ( "$testsuite" ne "" ) { print "</testsuite>\n"; }
      $testsuite="$2"; $testcase="$4"; $error_collect=""; print "<testsuite name=\"$testsuite\">\n";
    }
  }
  elsif ($line !~ /^ok$/ && $line !~ /^\d+..\d+$/) {
    $error_collect=$error_collect . $line;
  }
}
print "</testsuite>\n</testsuites>\n";
