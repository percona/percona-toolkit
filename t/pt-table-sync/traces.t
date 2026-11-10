#!/usr/bin/env perl

# This test's purpose: determine whether the SQL that pt-table-sync executes has
# distinct marker comments in it to identify the DML statements for DBAs to
# recognize. This is important for diagnosing what's in your binary log.

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
my $replica_dbh  = $replica1_dbh;

my $mysqlbinlog = `which mysqlbinlog`;
if ( $mysqlbinlog ) {
   chomp $mysqlbinlog;
}
elsif ( -x "$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqlbinlog" ) {
   $mysqlbinlog = "$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqlbinlog";
}

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}
elsif ( !$mysqlbinlog ) {
   plan skip_all => 'Cannot find mysqlbinlog';
}
else {
   plan tests => 2;
}

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

# We execute the test by changing a table so pt-table-sync will find something
# to modify.  Then we examine the binary log to find the SQL in it, and check
# that.
$sb->load_file('source', "t/pt-table-sync/samples/issue_533.sql");
my $pos = $source_dbh->selectrow_hashref("show ${source_status} status");
diag("Source position: $pos->{file} / $pos->{position}");

my @args = ('h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=t1', 't=t2', '--execute');
output(
   sub { pt_table_sync::main(@args) },
);

# The statement really ought to look like this:
# "DELETE FROM `test`.`t2` WHERE `i`='5' LIMIT 1 /*percona-toolkit
# src_db:test src_tbl:t1 src_dsn:P=12345,h=127.0.0.1,p=...,u=msandbox
# dst_db:test dst_tbl:t2 dst_dsn:P=12346,h=127.0.0.1,p=...,u=msandbox
# lock:1 transaction:0 changing_src:1 replicate:0 bidirectional:0 pid:0
# user:$ENV{USER} host:-*/
my $user   = $ENV{USER} ? "user:$ENV{USER}" : '';
my $output = `$mysqlbinlog /tmp/12345/data/$pos->{file} --start-position=$pos->{position} | grep 'percona-toolkit'`;
like(
   $output,
   qr/DELETE FROM.*test`.`t2.*percona-toolkit src_db:test.*$user/,
   "Trace message appended to change SQL"
);

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
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
