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
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 14;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

$sb->create_dbs($dbh, ['test']);

# Test --bulk-delete deletes in chunks
$sb->load_file('master', 't/pt-archiver/samples/table5.sql');
$output = `perl -I $trunk/t/pt-archiver/samples $cmd --plugin Plugin7 --no-ascend --limit 50 --bulk-delete --purge --where 1=1 --source D=test,t=table_5,F=$cnf --statistics 2>&1`;
like($output, qr/SELECT 105/, 'Fetched 105 rows');
like($output, qr/DELETE 105/, 'Deleted 105 rows');
like($output, qr/bulk_deleting *3 /, 'Issued only 3 DELETE statements');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_5"`;
is($output + 0, 0, 'Bulk delete removed all rows');

# Test that the generic plugin worked OK
$output = `/tmp/12345/use -N -e "select a from test.stat_test"`;
is($output + 0, 105, 'Generic plugin worked');

# Test --bulk-delete jails the WHERE safely in parens.
$output = output(
   sub { pt_archiver::main(qw(--dry-run --no-ascend --limit 50 --bulk-delete --purge --where 1=1), "--source", "D=test,t=table_5,F=$cnf", qw(--statistics)) },
);
like($output, qr/\(1=1\)/, 'WHERE clause is jailed');
unlike($output, qr/[^(]1=1/, 'WHERE clause is jailed');

# Test --bulk-delete works ok with a destination table
$sb->load_file('master', 't/pt-archiver/samples/table5.sql');
$output = output(
   sub { pt_archiver::main(qw(--no-ascend --limit 50 --bulk-delete --where 1=1), "--source", "D=test,t=table_5,F=$cnf", qw(--statistics --dest t=table_5_dest)) },
);
like($output, qr/SELECT 105/, 'Fetched 105 rows');
like($output, qr/DELETE 105/, 'Deleted 105 rows');
like($output, qr/INSERT 105/, 'Inserted 105 rows');
like($output, qr/bulk_deleting *3 /, 'Issued only 3 DELETE statements');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_5"`;
is($output + 0, 0, 'Bulk delete removed all rows');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_5_dest"`;
is($output + 0, 105, 'Bulk delete works OK with normal insert');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
