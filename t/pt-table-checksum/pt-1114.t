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
my $dsn = $sb->dsn_for('master');
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

diag("loading samples");
$sb->load_file('master', 't/pt-table-checksum/samples/pt-1114.sql');

my $master_port = $sb->port_for('master');
my $num_rows = 40000;

diag(`util/mysql_random_data_load --host=127.0.0.1 --port=$master_port --user=msandbox --password=msandbox test t1 $num_rows`);

$dbh->do('set global innodb_stats_persistent=0;');
$dbh->do('DELETE FROM test.t1');

my @args = ($dsn); 
my $output;
my $exit_status;

# Test #1 
$output = output(
   sub { $exit_status = pt_table_checksum::main(@args) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Exit status OK",
);
diag($output);

like(
    $output,
    qr/0\s+0\s+0\s+0\s+1\s+0\s+\d+\.\d+\s+test\.t1/,
    "Checksumed test.t1 even when it is empty",
);

$dbh->do('SET GLOBAL binlog_format="STATEMENT"');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
