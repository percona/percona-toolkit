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
# that such-and-such happened on specific replica hosts, but
# the sandbox servers are all on one host so all replicas have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
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
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($source_dsn, qw(--set-vars innodb_lock_wait_timeout=3),
                   '--chunk-size', '50'); 
my $output;
my $row;
my $scripts = "$trunk/t/pt-table-checksum/scripts/";

# ############################################################################
# Tool should check all replicas' lag, so replica2, not just replica1.
# ############################################################################

# Must have empty checksums table for these tests.
$source_dbh->do('drop table if exists percona.checksums');

# Must not be lagging.
$sb->wait_for_replicas();

# This big fancy command waits until it sees the checksum for sakila.city
# in the repl table on the source, then it stops replica2 for 2 seconds,
# then starts it again.
# TEST_WISHLIST PLUGIN_WISHLIST: do this with a plugin to the tool itself,
# not in this unreliable fashion.

# Notice there are 3 *different* wait type commands involved
# Final integer in the line is the run-time allowed for the "outermost" wait (wait-to-exec). If it is absent it defaults to 1, which may not be enough for sakila.city# chunk to appear (at least on slow systems)

system("$trunk/util/wait-to-exec '$scripts/wait-for-chunk.sh 12345 sakila city 1' '$scripts/exec-wait-exec.sh 12347 \"stop ${replica_name}\" 5 \"start ${replica_name}\"' 12 >/dev/null &");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d sakila)); },
   stderr => 1,
);

like(
   $output,
   qr/Replica h=127.0.0.1,P=12347 is stopped/,
   "--progress for replica lag"
) or diag($output);

like(
   $output,
   qr/sakila.store$/m,
   "Checksumming continues after waiting for replica lag"
);

# This test randomly fails, we need to know the reason
diag($output) if not is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "No errors after waiting for replica lag"
);

# Now wait until the SQL thread is started again.
$sb->wait_for_replicas();

# #############################################################################
# Wait for --replicate table to replicate.
# https://bugs.launchpad.net/percona-toolkit/+bug/1008778
# #############################################################################
$source_dbh->do("DROP DATABASE IF EXISTS percona");
wait_until(sub {
   my $dbs = $replica2_dbh->selectall_arrayref("SHOW DATABASES");
   return !grep { $_->[0] eq 'percona' } @$dbs;
});

$sb->load_file('source', "t/pt-table-checksum/samples/dsn-table.sql");

$replica2_dbh->do("STOP ${replica_name}");
wait_until(sub {
   my $ss = $replica2_dbh->selectrow_hashref("SHOW ${replica_name} STATUS");
   return $ss->{"${replica_name}_io_running"} eq 'Yes';
});


@args       = ($source_dsn, qw(--set-vars innodb_lock_wait_timeout=3),
                  '--progress', 'time,2', '--max-load', '', '--chunk-size', '500');

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

$replica2_dbh->do("START ${replica_name}");

$sb->wait_for_replicas();

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
