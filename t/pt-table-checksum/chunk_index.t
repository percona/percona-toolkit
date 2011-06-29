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
   plan tests => 6;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my @args = ('-F', $cnf, 'h=127.1', qw(-d issue_519 --explain --chunk-size 3));

$sb->load_file('master', "t/pt-table-checksum/samples/issue_519.sql");

my $default_output = "issue_519 t     SELECT /*issue_519.t:1/5*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `i`, `y`, `t`, CONCAT(ISNULL(`t`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_519`.`t` FORCE INDEX (`PRIMARY`) WHERE (`i` = 0)
issue_519 t     `i` = 0
issue_519 t     `i` > 0 AND `i` < '4'
issue_519 t     `i` >= '4' AND `i` < '7'
issue_519 t     `i` >= '7' AND `i` < '10'
issue_519 t     `i` >= '10'
";

$output = output(
   sub { pt_table_checksum::main(@args) },
);

is(
   $output,
   $default_output,
   "Chooses chunk index by default"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(--chunk-index dog)) },
);

is(
   $output,
   $default_output,
   "Chooses chunk index if --chunk-index doesn't exist"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(--chunk-index myidx)) },
);

is(
   $output,
"issue_519 t     SELECT /*issue_519.t:1/5*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `i`, `y`, `t`, CONCAT(ISNULL(`t`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_519`.`t` FORCE INDEX (`myidx`) WHERE (`i` = 0)
issue_519 t     `i` = 0
issue_519 t     `i` > 0 AND `i` < '4'
issue_519 t     `i` >= '4' AND `i` < '7'
issue_519 t     `i` >= '7' AND `i` < '10'
issue_519 t     `i` >= '10'
",
   "Use --chunk-index"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(--chunk-index y)) },
);

is(
   $output,
"issue_519 t     SELECT /*issue_519.t:1/5*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `i`, `y`, `t`, CONCAT(ISNULL(`t`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_519`.`t` FORCE INDEX (`y`) WHERE (`y` = 0)
issue_519 t     `y` = 0
issue_519 t     `y` > 0 AND `y` < '2003'
issue_519 t     `y` >= '2003' AND `y` < '2006'
issue_519 t     `y` >= '2006' AND `y` < '2009'
issue_519 t     `y` >= '2009'
",
   "Chunks on left-most --chunk-index column"
);

# Disabling the index hint with --no-use-index should not affect the
# chunks.  It should only remove the FORCE INDEX clause from the SQL.
$output = output(
   sub { pt_table_checksum::main(@args, qw(--chunk-index y --no-use-index)) },
);

is(
   $output,
"issue_519 t     SELECT /*issue_519.t:1/5*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `i`, `y`, `t`, CONCAT(ISNULL(`t`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_519`.`t`  WHERE (`y` = 0)
issue_519 t     `y` = 0
issue_519 t     `y` > 0 AND `y` < '2003'
issue_519 t     `y` >= '2003' AND `y` < '2006'
issue_519 t     `y` >= '2006' AND `y` < '2009'
issue_519 t     `y` >= '2009'
",
   "No index hint with --no-use-index"
);


# #############################################################################
# Issue 378: Make mk-table-checksum try to use the index preferred by the
# optimizer
# #############################################################################

# This issue affect --chunk-index.  Tool should auto-choose chunk-index
# when --where is given but no explicit --chunk-index|column is given.
# Given the --where clause, MySQL will prefer the y index.

$output = output(
   sub { pt_table_checksum::main(@args, "--where", "y > 2009") },
);

is(
   $output,
"issue_519 t     SELECT /*issue_519.t:1/5*/ 0 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `i`, `y`, `t`, CONCAT(ISNULL(`t`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_519`.`t` FORCE INDEX (`y`) WHERE (`y` = 0) AND ((y > 2009))
issue_519 t     `y` = 0
issue_519 t     `y` > 0 AND `y` < '2003'
issue_519 t     `y` >= '2003' AND `y` < '2006'
issue_519 t     `y` >= '2006' AND `y` < '2009'
issue_519 t     `y` >= '2009'
",
   "Auto-chosen --chunk-index for --where (issue 378)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
