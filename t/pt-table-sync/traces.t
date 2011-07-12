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
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

my $mysqlbinlog = `which mysqlbinlog`;
chomp $mysqlbinlog if $mysqlbinlog;

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
elsif ( !$mysqlbinlog ) {
   plan skip_all => 'Cannot find mysqlbinlog';
}
else {
   plan tests => 1;
}

my $output;
my @args = ('h=127.0.0.1,P=12346,u=msandbox,p=msandbox', qw(--sync-to-master --execute -t onlythisdb.t));

diag(`$trunk/sandbox/test-env reset`);
$sb->load_file('master', "t/pt-table-sync/samples/issue_533.sql");
sleep 1;

$slave_dbh->do('insert into onlythisdb.t values (5)');

output(
   sub { pt_table_sync::main(@args) },
);

my $binlog = $master_dbh->selectrow_arrayref('show master logs');

$output = `$mysqlbinlog /tmp/12345/data/$binlog->[0] | grep maatkit`;
$output =~ s/pid:\d+/pid:0/ if $output;
$output =~ s/host:\S+?\*/host:-*/ if $output;
is(
   $output,
"DELETE FROM `onlythisdb`.`t` WHERE `i`='5' LIMIT 1 /*maatkit src_db:onlythisdb src_tbl:t src_dsn:P=12345,h=127.0.0.1,p=...,u=msandbox dst_db:onlythisdb dst_tbl:t dst_dsn:P=12346,h=127.0.0.1,p=...,u=msandbox lock:1 transaction:0 changing_src:1 replicate:0 bidirectional:0 pid:0 user:$ENV{USER} host:-*/
",
   "Trace message appended to change SQL"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
