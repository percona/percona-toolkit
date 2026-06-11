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
use SqlModes;
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
else {
   plan tests => 3;
}

diag("loading samples");
$sb->load_file('source', 't/pt-table-checksum/samples/pt-226.sql');

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = $sb->dsn_for('source');
diag("setting up the replicas");
my $replica_dbh = $sb->get_dbh_for('replica1');
# Create differences

$replica_dbh->do('DELETE FROM `test`.`joinit` WHERE i > 90');
$replica_dbh->do('FLUSH TABLES');
$dbh->do('SET GLOBAL binlog_format="ROW"');

my @args       = ($source_dsn, "--set-vars", "innodb_lock_wait_timeout=50", 
                               "--ignore-databases", "mysql",
                               "--nocheck-replication-filters"); 
my $output;
my $exit_status;

# Test #1 
$output = output(
   sub { $exit_status = pt_table_checksum::main(@args) },
   stderr => 1,
);

isnt(
   $exit_status,
   0,
   "PT-226 SET binlog_format='STATEMENT' exit status",
);

like(
    $output,
    qr/1\s+100\s+10\s+1\s+0\s+.*test.joinit/,
    "PT-226 table joinit has differences",
);

$dbh->do('SET GLOBAL binlog_format="STATEMENT"');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
