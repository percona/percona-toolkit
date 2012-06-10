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
   plan tests => 18;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
# Add path to samples to Perl's INC so the tool can find the module.
my $cmd = "perl -I $trunk/t/pt-archiver/samples $trunk/bin/pt-archiver";

$sb->create_dbs($dbh, ['test']);

# Check plugin that does nothing
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = `$cmd --where 1=1 --source m=Plugin1,D=test,t=table_1,F=$cnf --dest t=table_2 2>&1`;
is($output, '', 'Loading a blank plugin worked OK');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
is($output + 0, 4, 'Purged no rows ok b/c of blank plugin');

# Test that ascending index check doesn't leave any holes on a unique index when
# there is a plugin that always says rows are archivable
$sb->load_file('master', 't/pt-archiver/samples/table5.sql');
$output = `$cmd --source m=Plugin2,D=test,t=table_5,F=$cnf --purge --limit 50 --where 'a<current_date - interval 1 day' 2>&1`;
is($output, '', 'No errors with strictly ascending index');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_5"`;
is($output + 0, 0, 'Purged completely with strictly ascending index');

# Check plugin that adds rows to another table (same thing as --dest, but on
# same db handle)
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');
$output = `$cmd --where 1=1 --source m=Plugin3,D=test,t=table_1,F=$cnf --purge 2>&1`;
is($output, '', 'Running with plugin did not die');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_1"`;
is($output + 0, 0, 'Purged all rows ok with plugin');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_2"`;
is($output + 0, 4, 'Plugin archived all rows to table_2 OK');

# Check plugin that does ON DUPLICATE KEY UPDATE on insert
$sb->load_file('master', 't/pt-archiver/samples/tables7-9.sql');
$output = `$cmd --where 1=1 --source D=test,t=table_7,F=$cnf --dest m=Plugin4,t=table_8 2>&1`;
is($output, '', 'Loading plugin worked OK');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_7"`;
is($output + 0, 0, 'Purged all rows ok with plugin');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_8"`;
is($output + 0, 2, 'Plugin archived all rows to table_8 OK');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_9"`;
is($output + 0, 1, 'ODKU made one row');
$output = `/tmp/12345/use -N -e "select a, b, c from test.table_9"`;
like($output, qr/1\s+3\s+6/, 'ODKU added rows up');

# Check plugin that sets up and archives a temp table
$sb->load_file('master', 't/pt-archiver/samples/table10.sql');
$output = `$cmd --where 1=1 --source m=Plugin5,D=test,t=tmp_table,F=$cnf --dest t=table_10 2>&1`;
is($output, '', 'Loading plugin worked OK');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_10"`;
is($output + 0, 2, 'Plugin archived all rows to table_10 OK');

# Check plugin that sets up and archives to one or the other table depending
# on even/odd
$sb->load_file('master', 't/pt-archiver/samples/table10.sql');
$sb->load_file('master', 't/pt-archiver/samples/table13.sql');
$output = `$cmd --where 1=1 --source D=test,t=table_13,F=$cnf --dest m=Plugin6,t=table_10 2>&1`;
is($output, '', 'Loading plugin worked OK');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_even"`;
is($output + 0, 1, 'Plugin archived all rows to table_even OK');
$output = `/tmp/12345/use -N -e "select count(*) from test.table_odd"`;
is($output + 0, 2, 'Plugin archived all rows to table_odd OK');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
