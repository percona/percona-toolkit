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
   plan tests => 5;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables. Setting
# --chunk-size may help prevent the tool from running too fast and finishing
# before the TEST_WISHLIST job below finishes. (Or, it might just make things
# worse. This is a random stab in the dark. There is a problem either way.)
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3),
                  '--progress', 'time,1', '--max-load', '', '--chunk-size', '500'); 
my $output;
my $row;
my $scripts = "$trunk/t/pt-table-checksum/scripts/";

# ############################################################################
# Tool should check all slaves' lag, so slave2, not just slave1.
# ############################################################################

# Must have empty checksums table for these tests.
$master_dbh->do('drop table if exists percona.checksums');

# Must not be lagging.
$sb->wait_for_slaves();

# This big fancy command waits until it sees the checksum for sakila.city
# in the repl table on the master, then it stops slave2 for 2 seconds,
# then starts it again.
# TEST_WISHLIST PLUGIN_WISHLIST: do this with a plugin to the tool itself,
# not in this unreliable fashion.
system("$trunk/util/wait-to-exec '$scripts/wait-for-chunk.sh 12345 sakila city 1' '$scripts/exec-wait-exec.sh 12347 \"stop slave sql_thread\" 2 \"start slave sql_thread\"' 4 >/dev/null &");

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

# Now wait until the SQL thread is started again.
$sb->wait_for_slaves();

# #############################################################################
# Wait for --replicate table to replicate.
# https://bugs.launchpad.net/percona-toolkit/+bug/1008778
# #############################################################################
$master_dbh->do("DROP DATABASE IF EXISTS percona");
wait_until(sub {
   my $dbs = $slave2_dbh->selectall_arrayref("SHOW DATABASES");
   return !grep { $_->[0] eq 'percona' } @$dbs;
});

$sb->load_file('master', "t/pt-table-checksum/samples/dsn-table.sql");

$slave2_dbh->do("STOP SLAVE");
wait_until(sub {
   my $ss = $slave2_dbh->selectrow_hashref("SHOW SLAVE STATUS");
   return $ss->{slave_io_running} eq 'Yes';
});

($output) = PerconaTest::full_output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.country),
      "--recursion-method", "dsn=F=/tmp/12345/my.sandbox.cnf,t=dsns.dsns");
   },
   wait_for => 3,  # wait this many seconds then kill that ^
);

like(
   $output,
   qr/Waiting for the --replicate table to replicate to h=127.1,P=12347/,
   "--progress for --replicate table (bug 1008778)"
);

$slave2_dbh->do("START SLAVE");
$sb->wait_for_slaves();

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
