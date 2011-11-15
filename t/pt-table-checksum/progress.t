#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave2_dbh = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}
else {
   plan tests => 3;
}

# Must have empty checksums table for these tests.
$master_dbh->do('drop table if exists percona.checksums');

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3),
                  '--progress', 'time,1', '--max-load', ''); 
my $output;
my $row;
my $scripts = "$trunk/t/pt-table-checksum/scripts/";

# ############################################################################
# Tool should check all slaves' lag, so slave2, not just slave1.
# ############################################################################
wait_until(  # slaves aren't lagging
   sub {
      $row = $slave1_dbh->selectrow_hashref('show slave status');
      return 0 if $row->{Seconds_Behind_Master};
      $row = $slave2_dbh->selectrow_hashref('show slave status');
      return 0 if $row->{Seconds_Behind_Master};
      return 1;
   }
) or die "Slaves are still lagging";

# This big fancy command waits until it sees the checksum for sakila.city
# in the repl table on the master, then it stops slave2 for 2 seconds,
# then starts it again.
system("$trunk/util/wait-to-exec '$scripts/wait-for-chunk.sh 12345 sakila city 1' '$scripts/exec-wait-exec.sh 12347 \"stop slave sql_thread\" 2 \"start slave sql_thread\"' 3 >/dev/null &");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d sakila)); },
   stderr => 1,
);

like(
   $output,
   qr/Replica h=127.0.0.1,P=12347 is stopped/,
   "--progress for slave lag"
);

like(
   $output,
   qr/sakila.store$/m,
   "Checksumming continues after waiting for slave lag"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "No errors after waiting for slave lag"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
diag(`$trunk/sandbox/test-env reset >/dev/null`);
exit;
