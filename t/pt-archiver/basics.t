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

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

# Make sure load works.
$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$rows = $dbh->selectrow_arrayref('select count(*) from test.table_1')->[0];
if ( ($rows || 0) != 4 ) {
   plan skip_all => 'Failed to load tables1-4.sql';
}
else {
   plan tests => 24;
}

my @args = qw(--dry-run --where 1=1);

# ###########################################################################
# These are dry-run tests of various options to test that the correct
# SQL statements are generated.
# ###########################################################################

# Test --for-update
$output = output(sub {pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$cnf", qw(--for-update --purge)) });
like($output, qr/SELECT .*? FOR UPDATE/, '--for-update');

# Test --share-lock
$output = output(sub {pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$cnf", qw(--share-lock --purge)) });
like($output, qr/SELECT .*? LOCK IN SHARE MODE/, '--share-lock');

# Test --quick-delete
$output = output(sub {pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$cnf", qw(--quick-delete --purge)) });
like($output, qr/DELETE QUICK/, '--quick-delete');

# Test --low-priority-delete
$output = output(sub {pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$cnf", qw(--low-priority-delete --purge)) });
like($output, qr/DELETE LOW_PRIORITY/, '--low-priority-delete');

# Test --low-priority-insert
$output = output(sub {pt_archiver::main(@args, qw(--dest t=table_2), '--source', "D=test,t=table_1,F=$cnf", qw(--low-priority-insert)) });
like($output, qr/INSERT LOW_PRIORITY/, '--low-priority-insert');

# Test --delayed-insert
$output = output(sub {pt_archiver::main(@args, qw(--dest t=table_2), '--source', "D=test,t=table_1,F=$cnf", qw(--delayed-insert)) });
like($output, qr/INSERT DELAYED/, '--delay-insert');

# Test --replace
$output = output(sub {pt_archiver::main(@args, qw(--dest t=table_2), '--source', "D=test,t=table_1,F=$cnf", qw(--replace)) });
like($output, qr/REPLACE/, '--replace');

# Test --high-priority-select
$output = output(sub {pt_archiver::main(@args, qw(--high-priority-select --dest t=table_2 --source), "D=test,t=table_1,F=$cnf", qw(--replace)) });
like($output, qr/SELECT HIGH_PRIORITY/, '--high-priority-select');

# Test --columns
$output = output(sub {pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$cnf", '--columns', 'a,b', qw(--purge)) });
like($output, qr{SELECT /\*!40001 SQL_NO_CACHE \*/ `a`,`b` FROM}, 'Only got specified columns');

# Test --primary-key-only
$output = output(sub {pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$cnf", qw(--primary-key-only --purge)) });
like($output, qr{SELECT /\*!40001 SQL_NO_CACHE \*/ `a` FROM}, '--primary-key-only works');

# Test that tables must have same columns
$output = output(sub {pt_archiver::main(@args, qw(--dest t=table_4 --source), "D=test,t=table_1,F=$cnf", qw(--purge)) }, stderr=>1);
like($output, qr/The following columns exist in --source /, 'Column check throws error');
$output = output(sub {pt_archiver::main(@args, qw(--no-check-columns --dest t=table_4 --source), "D=test,t=table_1,F=$cnf", qw(--purge)) });
like($output, qr/SELECT/, 'I can disable the check OK');

# ###########################################################################
# These are online tests that check various options.
# ###########################################################################

shift @args;  # remove --dry-run

# Test --why-quit and --statistics output
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = output(sub {pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$cnf", qw(--purge --why-quit --statistics)) });
like($output, qr/Started at \d/, 'Start timestamp');
like($output, qr/Source:/, 'source');
like($output, qr/SELECT 4\nINSERT 0\nDELETE 4\n/, 'row counts');
like($output, qr/Exiting because there are no more rows/, 'Exit reason');

# Test basic functionality with OPTIMIZE
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = output(sub {pt_archiver::main(@args, qw(--optimize ds --source), "D=test,t=table_1,F=$cnf", qw(--purge)) });
is($output, '', 'OPTIMIZE did not fail');

# Test an empty table
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = `/tmp/12345/use -N -e "delete from test.table_1"`;
$output = output(sub {pt_archiver::main(@args, '--source', "D=test,t=table_1,F=$cnf", qw(--purge)) });
is($output, "", 'Empty table OK');

# Test the output
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = `$trunk/bin/pt-archiver --where 1=1 --source D=test,t=table_1,F=$cnf --purge --progress 2 2>&1 | awk '{print \$3}'`;
is($output, <<EOF
COUNT
0
2
4
4
EOF
,'Progress output looks okay');

# Statistics
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = output(sub {pt_archiver::main(@args, qw(--statistics --source), "D=test,t=table_1,F=$cnf", qw(--dest t=table_2)) });
like($output, qr/commit *10/, 'Stats print OK');

# Test --no-delete.
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = output(sub {pt_archiver::main(@args, qw(--no-delete --purge --source), "D=test,t=table_1,F=$cnf", qw(--dry-run)) });
like($output, qr/> /, '--no-delete implies strict ascending');
unlike($output, qr/>=/, '--no-delete implies strict ascending');
$output = output(sub {pt_archiver::main(@args, qw(--no-delete --purge --source), "D=test,t=table_1,F=$cnf") });
$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
is($output + 0, 4, 'All 4 rows are still there');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
