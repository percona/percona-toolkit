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

my $vp  = new VersionParser();
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
my $cnf='/tmp/12345/my.sandbox.cnf';
my @args = ('-F', $cnf, 'h=127.1', qw(-t osc.t));

diag(`/tmp/12345/use < $trunk/t/pt-table-checksum/samples/oversize-chunks.sql`);
$dbh->do('alter table osc.t drop index `i`');

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-size 10)) },
      "t/pt-table-checksum/samples/unchunkable-table.txt",
   ),
   "Skip unchunkable table"
);

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-size 1000)) },
      "t/pt-table-checksum/samples/unchunkable-table-small.txt",
   ),
   "Chunk unchunable table if smaller than chunk size"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
