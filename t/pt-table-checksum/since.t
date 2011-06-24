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

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 10;
}

my ($output, $output2);
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf -d test -t checksum_test 127.0.0.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/before.sql');

# Check --since
$output = `MKDEBUG=1 $cmd --since '"2008-01-01" - interval 1 day' --explain 2>&1 | grep 2007`;
like($output, qr/2007-12-31/, '--since is calculated as an expression');

# Check --since with --arg-table. The value in the --arg-table table
# ought to override the --since passed on the command-line.
$output = `$cmd --arg-table test.argtest --since 20 --explain`;
unlike($output, qr/`a`>=20/, 'Argtest overridden');
like($output, qr/`a`>='1'/, 'Argtest set to something else');

$output = `MKDEBUG=1 $cmd --since 'current_date + interval 1 day' -t test.blackhole 2>&1`;
like($output, qr/Finished chunk/, '--since does not crash on blackhole tables');

$output = `MKDEBUG=1 $cmd --since 'current_date + interval 1 day' 2>&1`;
like($output, qr/Skipping.*--since/, '--since skips tables');

$output = `$cmd --since 100 --explain`;
like($output, qr/`a`>='100'/, '--since adds WHERE clauses');

$output = `$cmd --since current_date 2>&1 | grep HASH`;
unlike($output, qr/HASH\(0x/, '--since does not f*** up table names');

# Check --since with --save-since
$output = `$cmd --arg-table test.argtest --save-since --chunk-size 50 -t test.chunk`;
$output2 = `/tmp/12345/use --skip-column-names -e "select since from test.argtest where tbl='chunk'"`;
is($output2 + 0, 1000, '--save-since saved the maxrow');
$output = `$cmd --arg-table test.argtest --save-since --chunk-size 50 -t test.argtest`;
$output2 = `/tmp/12345/use --skip-column-names -e "select since from test.argtest where tbl='argtest'"`;
like($output2, qr/^\d{4}-\d\d-\d\d/, '--save-since saved the current timestamp');

# #############################################################################
# Issue 121: mk-table-checksum and --since isn't working right on InnoDB tables
# #############################################################################

# Reusing issue_21.sql
$sb->load_file('master', 't/pt-table-checksum/samples/issue_21.sql'); 
$output = `$trunk/bin/pt-table-checksum --since 'current_date - interval 7 day' h=127.1,P=12345,u=msandbox,p=msandbox -t test.issue_21`;
like($output, qr/test\s+issue_21\s+0\s+127\.1\s+InnoDB/, 'InnoDB table is checksummed with temporal --since');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
