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
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
} elsif ($sandbox_version lt '5.7') {
   plan skip_all => "Generated columns are only available in MySQL 5.7+";
} else {
   plan tests => 3;
}

diag("loading samples");

$sb->load_file('master', 't/pt-table-checksum/samples/pt-225.sql');

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = $sb->dsn_for('master');
diag("setting up the slaves");
my $slave_dbh = $sb->get_dbh_for('slave1');
# Create differences

$slave_dbh->do('DELETE FROM `test`.`sbtest1` WHERE id > 15');
$slave_dbh->do('FLUSH TABLES');

my @args       = ($master_dsn, "--set-vars", "innodb_lock_wait_timeout=50", 
                               "--ignore-databases", "mysql,sys,sakila,percona_test",
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
   "PT-225 virtual/generated columns are ignored - exit status",
);

like(
    $output,
    qr/1\s+\d+\s+\d+\s+\d+\s+.*test.sbtest1/,
    "PT-225 virtual/generated columns were ignored",
);


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
