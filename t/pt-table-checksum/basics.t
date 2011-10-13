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
   plan tests => 5;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3)); 

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

$sb->wipe_clean($master_dbh);
diag(`rm $outfile >/dev/null 2>&1`);

# ############################################################################
# Default checksum and results.  The tool does not technically require any
# options on well-configured systems (which the test env cannot be).  With
# nothing but defaults, it should create the repl table, checksum and check
# all tables, dynamically adjust the chunk size, and throttle itself and based
# on all slaves' lag.  We don't explicitly test throttling here; that's done
# in throttle.t.
# ############################################################################

ok(
   no_diff(
      sub { pt_table_checksum::main(@args) },
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
      sub { pt_table_checksum::main(@args, qw(--chunk-time 0)) },
      "$sample/static-chunk-size-results-5.1.txt",
      post_pipe => 'awk \'{print $2 " " $3 " " $4 " " $5 " " $6 " " $8}\'',
   ),
   "Static chunk size (--chunk-time 0)"
);

$row = $master_dbh->selectrow_arrayref("select count(*) from percona.checksums");
is(
   $row->[0],
   78,
   '78 checksums on master'
);

$row = $slave_dbh->selectrow_arrayref("select count(*) from percona.checksums");
is(
   $row->[0],
   78,
   '78 checksums on slave'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
