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
require "$trunk/bin/pt-table-usage";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';
my @args = ('--explain-extended', "F=$cnf");

my $in   = "$trunk/t/pt-table-usage/samples/in/";
my $out  = "t/pt-table-usage/samples/out/";

$output = output(
   sub { mk_table_usage::main(@args, "$in/slow003.txt") },
   stderr => 1,
);

like(
   $output,
   qr/No database/,
   "--explain-extended doesn't work without a database"
);

ok(
   no_diff(
      sub { mk_table_usage::main(@args, qw(-D sakila), "$in/slow003.txt") },
      "$out/slow003-002.txt",
   ),
   'EXPLAIN EXTENDED slow003.txt'
);

# #############################################################################
# Done.
# #############################################################################
exit;
