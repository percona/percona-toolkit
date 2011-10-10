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

use Data::Dumper;
use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !@{$master_dbh->selectall_arrayref('show databases like "sakila"')} ) {
   plan skip_all => 'sakila database is not loaded';
}
else {
   plan tests => 4;
}

my $cnf = '/tmp/12345/my.sandbox.cnf';
my $dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';

my $row;
my $output;
my $sample  = "t/pt-table-checksum/samples/";
my $outfile = '/tmp/pt-table-checksum-results';
my $repl_db = 'percona';

sub reset_repl_db {
   $master_dbh->do("drop database if exists $repl_db");
   $master_dbh->do("create database $repl_db");
   $master_dbh->do("use $repl_db");
}

sub set_tx_isolation {
   my ( $level ) = @_;
   $master_dbh->do("set global transaction isolation level $level");
   $master_dbh->disconnect();
   $master_dbh = $sb->get_dbh_for('master');
   $row = $master_dbh->selectrow_arrayref("show variables like 'tx_isolation'");
   $level =~ s/ /-/g;
   $level = uc $level;
   is(
      $row->[1],
      $level,
      "Tx isolation $level"
   );
}

sub set_binlog_format {
   my ( $format ) = @_;
   $master_dbh->do("set global binlog_format=$format");
   $master_dbh->disconnect();
   $master_dbh = $sb->get_dbh_for('master');
   $row = $master_dbh->selectrow_arrayref("show variables like 'binlog_format'");
   $format = uc $format;
   is(
      $row->[1],
      $format,
      "Binlog format $format"
   );
}

reset_repl_db();
diag(`rm $outfile >/dev/null 2>&1`);

# ############################################################################
# Default checksum, results
# ############################################################################

# Check that without any special options (other than --create-replicate-table)
# the tool runs without errors or warnings and checksums all tables.
ok(
   no_diff(
      sub { pt_table_checksum::main($dsn, '--create-replicate-table',
         qw(--lock-wait-timeout 3)) },
      "$sample/default-results-5.1.txt",
      post_pipe => 'awk \'{print $2 " " $3 " " $4 " " $6 " " $8}\'',
   ),
   "Default checksum"
);

# On fast machines, the chunk size will probably be be auto-adjusted so
# large that all tables will be done in a single chunk without an index.
# Since this varies by default, there's no use checking the checksums
# other than to ensure that there's at one for each table.
$row = $master_dbh->selectrow_arrayref("select count(*) from percona.checksums");
cmp_ok(
   $row->[0], '>=', 37,
   'At least 37 checksums'
);

# ############################################################################
# Static chunk size (disable --chunk-time)
# ############################################################################

ok(
   no_diff(
      sub { pt_table_checksum::main($dsn, qw(--chunk-time 0),
         qw(--lock-wait-timeout 3)) },
      "$sample/static-chunk-size-results-5.1.txt",
      post_pipe => 'awk \'{print $2 " " $3 " " $4 " " $5 " " $6 " " $8}\'',
   ),
   "Static chunk size (--chunk-time 0)"
);

$row = $master_dbh->selectrow_arrayref("select count(*) from percona.checksums");
is(
   $row->[0],
   78,
   '78 checksums'
);

# #############################################################################
# Issue 720: mk-table-checksum --replicate should set transaction isolation
# level
# #############################################################################
#SKIP: {
#   skip "binlog_format test for MySQL v5.1+", 6
#      unless $sandbox_version gt '5.0';
#
#   empty_repl_tbl();
#   set_binlog_format('row');
#   set_tx_isolation('read committed');
#
#   $output = output(
#      sub { pt_table_checksum::main(@args) },
#      stderr   => 1,
#   );
#   like(
#      $output,
#      qr/test\s+checksum_test\s+0\s+127.0.0.1\s+MyISAM\s+1\s+83dcefb7/,
#      "Set session transaction isolation level repeatable read"
#   );
#
#   set_binlog_format('statement');
#   set_tx_isolation('repeatable read');
#}

# #############################################################################
# Done.
# #############################################################################
#$sb->wipe_clean($master_dbh);
exit;
