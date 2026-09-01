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
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');
my $dbh = $source_dbh;

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
   plan tests => 2;
}

$dbh->do("DROP TABLE IF EXISTS percona.checksums");
$sb->load_file('source', 't/pt-table-checksum/samples/pt-136.sql');
$sb->wait_for_replicas();
my $source_dsn = $sb->dsn_for('source');
my @args       = ($source_dsn, '--databases', 'db1', '--no-replicate-check'); 
my $output;
my $exit_status;

my ($orig_binlog_format_source) = $source_dbh->selectrow_array(q{SELECT @@global.binlog_format});
my ($orig_binlog_format_replica1) = $replica1_dbh->selectrow_array(q{SELECT @@global.binlog_format});
my ($orig_binlog_format_replica2) = $replica2_dbh->selectrow_array(q{SELECT @@global.binlog_format});

$source_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$source_dbh->do("SET binlog_format = 'STATEMENT'");
$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$replica1_dbh->do("SET binlog_format = 'STATEMENT'");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$replica2_dbh->do("SET binlog_format = 'STATEMENT'");
$replica2_dbh->do("START ${replica_name}");

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Checksum columns with mismatching collations",
) or BAIL_OUT("debug time");


# #############################################################################
# Done.
# #############################################################################
$source_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_source}'");
$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_replica1}'");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_replica2}'");
$replica2_dbh->do("START ${replica_name}");
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
