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

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 6;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3 -d issue_519 --explain --explain --chunk-size 3), '--max-load', '');
my $output;
my $out        = "t/pt-table-checksum/samples/";

$sb->load_file('master', "t/pt-table-checksum/samples/issue_519.sql");

ok(
   no_diff(
      sub { pt_table_checksum::main(@args) },
      "$out/chunkidx001.txt",
   ),
   "Chooses chunk index by default"
);

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-index dog)) },
      "$out/chunkidx001.txt",
   ),
   "Chooses chunk index if --chunk-index doesn't exist"
);

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-index myidx)) },
      "$out/chunkidx002.txt",
   ),
   "Use --chunk-index"
);

# XXX I'm not sure what this tests thinks it's testing because index y
# is a single column index, so there's really not "left-most".
ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-index y)) },
      "$out/chunkidx003.txt",
   ),
   "Chunks on left-most --chunk-index column"
);

# #############################################################################
# Issue 378: Make mk-table-checksum try to use the index preferred by the
# optimizer
# #############################################################################

# This issue affect --chunk-index.  Tool should auto-choose chunk-index
# when --where is given but no explicit --chunk-index|column is given.
# Given the --where clause, MySQL will prefer the y index.

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, "--where", "y > 2009") },
      "$out/chunkidx004.txt",
   ),
   "Auto-chosen --chunk-index for --where (issue 378)"
);

# If user specifies --chunk-index, then ignore the index MySQL wants to
# use (y in this case) and use the user's index.
ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-index PRIMARY),
         "--where", "y > 2009") },
      "$out/chunkidx005.txt",
   ),
   "Explicit --chunk-index overrides MySQL's index for --where"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
