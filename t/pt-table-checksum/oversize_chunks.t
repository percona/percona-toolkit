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

my $vp  = new VersionParser();
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my @args = ('-F', $cnf, 'h=127.1', qw(-t osc.t --chunk-size 10));

diag(`/tmp/12345/use < $trunk/t/pt-table-checksum/samples/oversize-chunks.sql`);

ok(
   no_diff(
      sub { mk_table_checksum::main(@args) },
      "t/pt-table-checksum/samples/oversize-chunks.txt",
   ),
   "Skip oversize chunk"
);

ok(
   no_diff(
      sub { mk_table_checksum::main(@args, qw(--chunk-size-limit 0)) },
      "t/pt-table-checksum/samples/oversize-chunks-allowed.txt"
   ),
   "Allow oversize chunk"
);

$output = `$trunk/bin/pt-table-checksum -F $cnf h=127.1 --chunk-size-limit 0.999 --chunk-size 100 2>&1`;
like(
   $output,
   qr/chunk-size-limit must be >= 1 or 0 to disable/,
   "Verify --chunk-size-limit size"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
