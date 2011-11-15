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
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 5;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3), '--max-load', ''); 

my $row;
my $output;

# --chunk-size is dynamic; it varies according to --chunk-time and
# however fast the server happens to be.  So test this is difficult
# because it's inherently nondeterministic.  However, with one table,
# the first chunk should equal the chunk size, and the 2nd chunk should
# larger, unless it takes your machine > 0.5s to select 100 rows.

pt_table_checksum::main(@args, qw(--quiet --chunk-size 100 -t sakila.city));

$row = $master_dbh->selectrow_arrayref("select lower_boundary, upper_boundary from percona.checksums where db='sakila' and tbl='city' and chunk=1");
is_deeply(
   $row,
   [1, 100],  # 100 rows for --chunk-size=100
   "First chunk is default size"
);

$row = $master_dbh->selectrow_arrayref("select lower_boundary, upper_boundary from percona.checksums where db='sakila' and tbl='city' and chunk=2");
is(
   $row->[0],
   101,
   "2nd chunk lower boundary"
);

cmp_ok(
   $row->[1] - $row->[0],
   '>',
   100,
   "2nd chunk is larger"
);

# ############################################################################
# Test --chunk-time here because it's linked to --chunk-size.
# ############################################################################

pt_table_checksum::main(@args, qw(--quiet --chunk-time 0 --chunk-size 100 -t sakila.city));

# There's 600 rows in sakila.city so there should be 6 chunks.
$row = $master_dbh->selectall_arrayref("select lower_boundary, upper_boundary from percona.checksums where db='sakila' and tbl='city'");
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
   "--chunk-time=0 disables auto-adjusting --chunk-size"
);

# ############################################################################
# Sub-second chunk-time.
# ############################################################################

$output = output(
   sub { pt_table_checksum::main(@args,
      qw(--quiet --chunk-time .001 -d mysql)) },
   stderr => 1,
);

unlike(
   $output,
   qr/Cannot checksum table/,
   "Very small --chunk-time doesn't cause zero --chunk-size"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
