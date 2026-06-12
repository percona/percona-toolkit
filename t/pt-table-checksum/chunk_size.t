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
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
else {
   plan tests => 8;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($source_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 

my $row;
my $output;
my $exit_status;

# --chunk-size is dynamic; it varies according to --chunk-time and
# however fast the server happens to be.  So test this is difficult
# because it's inherently nondeterministic.  However, with one table,
# the first chunk should equal the chunk size, and the 2nd chunk should
# larger, unless it takes your machine > 0.5s to select 100 rows.

pt_table_checksum::main(@args, qw(--quiet -t sakila.rental));

$row = $source_dbh->selectrow_arrayref("select lower_boundary, upper_boundary from percona.checksums where db='sakila' and tbl='rental' and chunk=1");
is_deeply(
   $row,
   [1, 1001],
   "First chunk is default size"
);

$row = $source_dbh->selectrow_arrayref("select lower_boundary, upper_boundary from percona.checksums where db='sakila' and tbl='rental' and chunk=2");
is(
   $row->[0],
   1002,
   "2nd chunk lower boundary"
);

cmp_ok(
   $row->[1] - $row->[0],
   '>',
   1000,
   "2nd chunk is larger"
);

# ############################################################################
# Explicit --chunk-size should override auto-sizing.
# ############################################################################

pt_table_checksum::main(@args, qw(--quiet --chunk-size 100 -t sakila.city));

# There's 600 rows in sakila.city so there should be 6 chunks.
$row = $source_dbh->selectall_arrayref("select lower_boundary, upper_boundary from percona.checksums where db='sakila' and tbl='city'");
is_deeply(
   $row,
   [
      [  1, 100],
      [101, 200],
      [201, 300],
      [301, 400],
      [401, 500],
      [501, 600],
      [undef,   1], # lower oob
      [600, undef], # upper oob
   ],
   "Explicit --chunk-size disables auto chunk sizing"
);

# ############################################################################
# Sub-second chunk-time.
# ############################################################################
SKIP: {
   skip "Too slow", 1;
$output = output(
   sub { pt_table_checksum::main(@args,
      qw(--quiet --chunk-time .001 -d mysql)) },
   stderr => 1,
);

unlike(
   $output,
   qr/Cannot checksum table/,
   "Very small --chunk-time doesn't cause zero --chunk-size"
) or diag($output);
}
# #############################################################################
# Bug 921700: pt-table-checksum doesn't add --where to chunk-oversize test
# on replicas
# #############################################################################
$sb->load_file('source', 't/pt-table-checksum/samples/600cities.sql');
$source_dbh->do("LOAD DATA LOCAL INFILE '$trunk/t/pt-table-checksum/samples/600cities.data' INTO TABLE test.t");
$source_dbh->do("SET SQL_LOG_BIN=0");
$source_dbh->do("DELETE FROM test.t WHERE id > 100");
$source_dbh->do("SET SQL_LOG_BIN=1");

# Now there are 100 rows on the source and 600 on the replica.
$output = output(
   sub { $exit_status = pt_table_checksum::main(@args,
      qw(-t test.t --chunk-size 100 --where id<=100)); },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Zero exit status (bug 185734)"
);

like(
   $output,
   qr/test.t$/,
   "Checksummed table (bug 185734)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
