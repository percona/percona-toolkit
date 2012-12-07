#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use PerconaTest;

use Time::HiRes qw(sleep time);
use POSIX qw(mkfifo);

# #########################################################################
# Issue 226: Fix mk-query-digest signal handling
# #########################################################################
my $pid_file = '/tmp/mqd.pid';
my $fifo     = '/tmp/mqd.fifo';

unlink $pid_file if -f $pid_file;
unlink $fifo     if -f $fifo;

my ($start, $end, $waited, $timeout);
SKIP: {
    skip("Not connected to a tty won't test --read-timeout with STDIN", 1)
        if !-t STDIN;
    use IO::File;
    STDIN->blocking(1);
    $timeout = wait_for(
        sub {
            $start = time;
            `$trunk/bin/pt-query-digest --read-timeout 2 --pid $pid_file 2>/dev/null`;
            return;
        },
        5,
    );
    $end    = time;
    $waited = $end - $start;
    if ( $timeout && -f $pid_file ) {
        # mqd ran longer than --read-timeout
        chomp(my $pid = slurp_file($pid_file));
        kill SIGTERM => $pid if $pid;
    }

    ok(
        $waited >= 2 && int($waited) <= 4,
        sprintf("--read-timeout 2 waited %.1f seconds reading STDIN", $waited)
    );
}

unlink $pid_file if -f $pid_file;
mkfifo $fifo, 0700;
system("$trunk/t/pt-query-digest/samples/write-to-fifo.pl $fifo 4 &");

$timeout = wait_for(
   sub {
      $start = time;
      `$trunk/bin/pt-query-digest --read-timeout 2 --pid $pid_file $fifo`;
      return;
   },
   5,
);
$end    = time;
$waited = $end - $start;
if ( $timeout && -f $pid_file ) {
   # mqd ran longer than --read-timeout
   chomp(my $pid = slurp_file($pid_file));
   kill SIGTERM => $pid if $pid;
}

ok(
   $waited >= 2 && int($waited) <= 4,
   sprintf("--read-timeout 2 waited %.1f seconds reading a file", $waited)
);

unlink $pid_file if -f $pid_file;
unlink $fifo if -f $fifo;

# #############################################################################
# Done.
# #############################################################################
exit;
