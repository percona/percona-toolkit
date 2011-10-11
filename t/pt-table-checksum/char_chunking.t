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
   plan tests => 3;
}

my $output;
my $cnf  ='/tmp/12345/my.sandbox.cnf';
my @args = ("F=$cnf", qw(--lock-wait-timeout 3 --chunk-time 0 --chunk-size-limit 0 --tables test.ascii));

$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', "t/lib/samples/char-chunking/ascii.sql", 'test');

ok(
   no_diff(
      sub { pt_table_checksum::main(@args,
         qw(--chunk-size 20 --explain)) },
      "t/pt-table-checksum/samples/char-chunk-ascii-explain.txt",
   ),
   "Char chunk ascii, explain"
);

ok(
   no_diff(
      sub { pt_table_checksum::main(@args,
         qw(--chunk-size 20)) },
      "t/pt-table-checksum/samples/char-chunk-ascii.txt",
   ),
   "Char chunk ascii, chunk size 20"
);

ok(
   no_diff(
      sub { pt_table_checksum::main(@args,
         qw(--chunk-size 20 --chunk-size-limit 3)) },
      "t/pt-table-checksum/samples/char-chunk-ascii-oversize.txt",
   ),
   "Char chunk ascii, chunk size 20, with oversize"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
