#!/usr/bin/env perl

use strict;
require '../LogSplitter.pm';
require '../SlowLogParser.pm';

my $lp = new SlowLogParser();
my $ls = new LogSplitter(
   attribute  => 'Thread_id',
   saveto_dir => "/tmp/logettes/",
   lp         => $lp,
   verbose    => 1,
);

my @logs;
push @logs, split(',', $ARGV[0]) if @ARGV;
$ls->split_logs(\@logs);

exit;
