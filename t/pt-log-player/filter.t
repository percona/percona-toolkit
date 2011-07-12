#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-log-player";

my $output;
my $tmpdir = '/tmp/mk-log-player';
my $cmd = "$trunk/bin/pt-log-player --base-dir $tmpdir";

diag(`rm -rf $tmpdir 2>/dev/null; mkdir $tmpdir`);

# #############################################################################
# Issue 571: Add --filter to mk-log-player
# #############################################################################
`$cmd --split Thread_id $trunk/t/lib/samples/binlogs/binlog001.txt --type binlog --session-files 1 --filter '\$event->{arg} && \$event->{arg} eq \"foo\"'`;
ok(
   !-f "$tmpdir/sessions-1.txt",
   '--filter'
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -rf $tmpdir 2>/dev/null`);
exit;
