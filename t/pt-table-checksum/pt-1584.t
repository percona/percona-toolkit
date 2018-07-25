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
}
else {
   plan tests => 3;
}

diag("loading samples");
#$sb->load_file('master', 't/pt-table-checksum/samples/pt-226.sql');
$sb->load_file('master', 't/pt-table-checksum/samples/pt-1585.sql');
my $num_rows = 2000;
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test t1 $num_rows`);
diag("$num_rows sample rows loaded");

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = $sb->dsn_for('master');

my @args       = ($master_dsn, "--set-vars", "innodb_lock_wait_timeout=50", "--force-nibbling"); 
my $output;
my $exit_status;
warn @args;

$ENV{PTDEBUG} = 1;
# Test #1 
$output = output(
   sub { $exit_status = pt_table_checksum::main(@args) },
   stderr => 1,
);

delete $ENV{PTDEBUG};

is(
   $exit_status,
   0,
   "PT-226 SET binlog_format='STATEMENT' exit status",
);

like(
    $output,
    qr/1\s+100\s+0\s+1\s+0\s+.*test.joinit/,
    "PT-226 table joinit has differences",
);

$dbh->do('SET GLOBAL binlog_format="STATEMENT"');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
