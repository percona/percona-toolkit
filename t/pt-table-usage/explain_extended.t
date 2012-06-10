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
require "$trunk/bin/pt-table-usage";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 4;
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';
my @args = ('--explain-extended', "F=$cnf");

my $in   = "$trunk/t/pt-table-usage/samples/in";
my $out  = "t/pt-table-usage/samples/out";

$output = output(
   sub { pt_table_usage::main(@args, "$in/slow003.txt") },
);

like(
   $output,
   qr/^ERROR NO_DB_SELECTED/m,
   "--explain-extended doesn't work without a database"
);

ok(
   no_diff(
      sub { pt_table_usage::main(@args, qw(-D sakila), "$in/slow003.txt") },
      "$out/slow003-002.txt",
   ),
   'EXPLAIN EXTENDED slow003.txt'
);

$output = output(
   sub { pt_table_usage::main(@args, qw(-D sakila),
      '--query', 'select * from foo, bar where id=1') },
   stderr => 1,
);
is(
   $output,
   "",
   "No error if table doesn't exist"
);

# This test fails in Maatkit, too.  I guess I never finished writing it?
#ok(
#   no_diff(
#      sub { pt_table_usage::main(@args,
#         '--query', "select count(*), max(lmp), min(lmp) FROM ca.interval_lmp_rt_5min as A INNER JOIN ca.lmp_rt_5min as B ON A.datetime = B.datetime WHERE A.datetime = '2011-12-01 21:05:00'") },
#      "t/pt-table-usage/samples/ee.out",
#      stderr => 1,
#   ),
#   "New EXPLAIN EXTENDED"
#);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
