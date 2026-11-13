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
   plan tests => 3;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my ($output, $exit_code);

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

$sb->create_dbs($dbh, [qw(test)]);
$sb->load_file('source', 't/lib/samples/tables/issue-388.sql', 'test');

$sb->load_file('source', "t/pt-table-checksum/samples/pt-2250_dsns.sql");
$dbh->do("insert into test.foo values (null, 'john, smith')");

($output, $exit_code) = full_output(
   sub {
      pt_table_checksum::main(
         @args,
         'h=127.1,P=12345,u=msandbox,p=msandbox',
         qw(-d test),
         "--recursion-method=dsn=F=t/pt-archiver/samples/pt-191.cnf,D=dsns,t=dsns,h=127.0.0.1,P=12345,u=msandbox,p=msandbox")
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for recursion method dsn"
) or diag($output);

unlike(
   $output,
   qr/Can't connect to local MySQL server/,
   'No error message for recursion method dsn'
) or diag($output);

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
