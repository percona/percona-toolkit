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

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');
my $have_ncat = `which ncat 2>/dev/null`;

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}
elsif (!$have_ncat) {
   plan skip_all => 'ncat, required for this test, is not installed or not in PATH';
}
else {
   plan tests => 3;
}

$sb->load_file('source', "t/pt-table-sync/samples/pt-1205.sql");
$sb->wait_for_replicas();

# Setting up tunnels
my $pid1 = fork();

if ( !$pid1 ) {
   setpgrp;
   system('ncat -k -l localhost 3333 --sh-exec "ncat 127.0.0.1 12345"');
   exit;
}

my $pid2 = fork();

if ( !$pid2 ) {
   setpgrp;
   system('ncat -k -l localhost 3334 --sh-exec "ncat 127.0.0.1 12346"');
   exit;
}

my $o = new OptionParser();
my $q = new Quoter();
my $ms = new MasterSlave(
               OptionParser=>$o,
               DSNParser=>$dp,
               Quoter=>$q,
            );
my $ss = $ms->get_replica_status($replica1_dbh);

$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("CHANGE ${source_change} TO ${source_name}_PORT=3333, ${source_name}_LOG_POS=" . $ss->{"exec_${source_name}_log_pos"});
$replica1_dbh->do("START ${replica_name}");

my $output = `$trunk/bin/pt-table-sync h=127.0.0.1,P=3334,u=msandbox,p=msandbox --database=test --table=t1 --sync-to-source --execute --verbose 2>&1`;

unlike(
   $output,
   qr/The replica is connected to \d+ but the source's port is/,
   'No error for redirected replica'
) or diag($output);

kill -1, getpgrp($pid1);
kill -1, getpgrp($pid2);

$replica1_dbh->do("STOP ${replica_name}");
$ss = $ms->get_replica_status($replica1_dbh);
$replica1_dbh->do("CHANGE ${source_change} TO ${source_name}_PORT=12347, ${source_name}_LOG_POS=" . $ss->{"exec_${source_name}_log_pos"});
$replica1_dbh->do("START ${replica_name} SQL_THREAD");

$output = `$trunk/bin/pt-table-sync h=127.0.0.1,P=12346,u=msandbox,p=msandbox --database=test --table=t1 --sync-to-source --execute --verbose 2>&1`;

like(
   $output,
   qr/The server specified as a source has no connected replicas/,
   'Error printed for the wrong source'
) or diag($output);

$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("CHANGE ${source_change} TO ${source_name}_PORT=12345, ${source_name}_LOG_POS=" . $ss->{"exec_${source_name}_log_pos"});
$replica1_dbh->do("START ${replica_name}");
# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
