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
   plan tests => 2;
}

$sb->load_file('source', 't/pt-table-checksum/samples/issue_1485195.sql');
# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox,D=my_binary_database';
my @args       = ($source_dsn, qw(--replicate my_binary_database.my_table -t percona_test.checksums)); 
my $output;

$output = output(
   sub { pt_table_checksum::main(@args) },
   stderr => 1,
);

# We do not count these tables by default, because their presense depends from 
# previously running tests
my $extra_tables = $dbh->selectrow_arrayref("select count(*) from percona_test.checksums where db_tbl in ('mysql.plugin', 'mysql.func', 'mysql.proxies_priv', 'mysql.component');")->[0];

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   $sandbox_version ge '8.0' ? 28 + $extra_tables : $sandbox_version lt '5.7' ? 24 : 23  + $extra_tables,
   "Large BLOB/TEXT/BINARY Checksum"
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
