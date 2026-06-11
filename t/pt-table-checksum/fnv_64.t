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
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($source_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $sample     = "t/pt-table-checksum/samples/";
my $row;
my $output;

$sb->create_dbs($source_dbh, [qw(test)]);

eval { $source_dbh->do('DROP FUNCTION IF EXISTS fnv_64'); };
eval { $source_dbh->do("CREATE FUNCTION fnv_64 RETURNS INTEGER SONAME 'libfnv_udf.so';"); };
if ( $EVAL_ERROR ) {
   chomp $EVAL_ERROR;
   plan skip_all => "No FNV_64 UDF lib"
}
else {
   plan tests => 7;
}

# ############################################################################
# First test the the FNV function works in MySQL and gives the correct results.
# ############################################################################

($row) = $source_dbh->selectrow_array("select fnv_64(1)");
is(
   $row,
   "-6320923009900088257",
   "FNV_64(1)"
);

($row) = $source_dbh->selectrow_array("select fnv_64('hello, world')");
is(
   $row,
   "6062351191941526764",
   "FNV_64('hello, world')"
);

# ############################################################################
# Check that FNV_64() is actually used in the checksum queries.
# ############################################################################

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--function FNV_64),
         qw(--explain --chunk-size 100 --chunk-time 0),
         '-d', 'sakila', '-t', 'city,film_actor') },
      "$sample/fnv64-sakila-city.txt",
   ),
   "--function FNV_64"
);

# ############################################################################
# Check that actually using FNV_64() doesn't cause problems.
# ############################################################################

$output = output(      
   sub { pt_table_checksum::main(@args, qw(--function FNV_64),
      qw(--chunk-size 100 --chunk-time 0),
      '-d', 'sakila', '-t', 'city,film_actor') },
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "No errors"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "No diffs"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "No skipped"
);

# #############################################################################
# Done.
# #############################################################################
$source_dbh->do('DROP FUNCTION IF EXISTS fnv_64');
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
