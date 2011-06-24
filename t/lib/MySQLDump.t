#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use MySQLDump;
use Quoter;
use DSNParser;
use Sandbox;
use MaatkitTest;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}
else { 
   plan tests => 12;
}

$sb->create_dbs($dbh, ['test']);

my $du = new MySQLDump();
my $q  = new Quoter();

my $dump;

# TODO: get_create_table() seems to return an arrayref sometimes!

SKIP: {
   skip 'Sandbox master does not have the sakila database', 10
      unless @{$dbh->selectcol_arrayref('SHOW DATABASES LIKE "sakila"')};

   $dump = $du->dump($dbh, $q, 'sakila', 'film', 'table');
   like($dump, qr/language_id/, 'Dump sakila.film');

   $dump = $du->dump($dbh, $q, 'mysql', 'film', 'triggers');
   ok(!defined $dump, 'no triggers in mysql');

   $dump = $du->dump($dbh, $q, 'sakila', 'film', 'triggers');
   like($dump, qr/AFTER INSERT/, 'dump triggers');

   $dump = $du->dump($dbh, $q, 'sakila', 'customer_list', 'table');
   like($dump, qr/CREATE TABLE/, 'Temp table def for view/table');
   like($dump, qr/DROP TABLE/, 'Drop temp table def for view/table');
   like($dump, qr/DROP VIEW/, 'Drop view def for view/table');
   unlike($dump, qr/ALGORITHM/, 'No view def');

   $dump = $du->dump($dbh, $q, 'sakila', 'customer_list', 'view');
   like($dump, qr/DROP TABLE/, 'Drop temp table def for view');
   like($dump, qr/DROP VIEW/, 'Drop view def for view');
   like($dump, qr/ALGORITHM/, 'View def');
};

# #############################################################################
# Issue 170: mk-parallel-dump dies when table-status Data_length is NULL
# #############################################################################

# The underlying problem for issue 170 is that MySQLDump doesn't eval some
# of its queries so when MySQLFind uses it and hits a broken table it dies.

diag(`cp $trunk/t/lib/samples/broken_tbl.frm /tmp/12345/data/test/broken_tbl.frm`);
my $output = '';
eval {
   local *STDERR;
   open STDERR, '>', \$output;
   $dump = $du->dump($dbh, $q, 'test', 'broken_tbl', 'table');
};
is(
   $EVAL_ERROR,
   '',
   'No error dumping broken table'
);
like(
   $output,
   qr/table may be damaged.+selectrow_hashref failed/s,
   'Warns about possibly damaged table'
);

$sb->wipe_clean($dbh);
exit;
