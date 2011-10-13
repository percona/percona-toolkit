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

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 6;
}


my $cnf='/tmp/12345/my.sandbox.cnf';
# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3 -d issue_519 --explain --explain --chunk-size 3));
my $output;

$sb->load_file('master', "t/pt-table-checksum/samples/issue_519.sql");

my $default_output = "--
-- issue_519.t
--

REPLACE INTO `percona`.`checksums` (db, tbl, chunk, chunk_index, lower_boundary, upper_boundary, this_cnt, this_crc) SELECT ?, ?, ?, ?, ?, ?, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `i`, `y`, `t`, CONCAT(ISNULL(`t`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_519`.`t` FORCE INDEX(`PRIMARY`) WHERE ((`i` >= ?)) AND ((`i` <= ?)) ORDER BY `i` /*checksum chunk*/

SELECT /*!40001 SQL_NO_CACHE */ `i` FROM `issue_519`.`t` FORCE INDEX(`PRIMARY`) WHERE ((`i` >= ?)) ORDER BY `i` LIMIT ?, 2 /*next chunk boundary*/

1 1 3
2 4 6
3 7 9
4 10 11

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
"--
-- issue_519.t
--

REPLACE INTO `percona`.`checksums` (db, tbl, chunk, chunk_index, lower_boundary, upper_boundary, this_cnt, this_crc) SELECT ?, ?, ?, ?, ?, ?, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `i`, `y`, `t`, CONCAT(ISNULL(`t`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_519`.`t` FORCE INDEX(`myidx`) WHERE ((`i` > ?) OR (`i` = ? AND `y` >= ?)) AND ((`i` < ?) OR (`i` = ? AND `y` <= ?)) ORDER BY `i`, `y` /*checksum chunk*/

SELECT /*!40001 SQL_NO_CACHE */ `i`, `i`, `y` FROM `issue_519`.`t` FORCE INDEX(`myidx`) WHERE ((`i` > ?) OR (`i` = ? AND `y` >= ?)) ORDER BY `i`, `y` LIMIT ?, 2 /*next chunk boundary*/

1 1,1,2000 3,3,2002
2 4,4,2003 6,6,2005
3 7,7,2006 9,9,2008
4 10,10,2009 11,11,2010

",
   "Use --chunk-index"
);

$output = output(
   sub { pt_table_checksum::main(@args, qw(--chunk-index y)) },
);

# XXX I'm not sure what this tests thinks it's testing because index y
# is a single column index, so there's really not "left-most".
is(
   $output,
"--
-- issue_519.t
--

REPLACE INTO `percona`.`checksums` (db, tbl, chunk, chunk_index, lower_boundary, upper_boundary, this_cnt, this_crc) SELECT ?, ?, ?, ?, ?, ?, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `i`, `y`, `t`, CONCAT(ISNULL(`t`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_519`.`t` FORCE INDEX(`y`) WHERE ((`y` >= ?)) AND ((`y` <= ?)) ORDER BY `y` /*checksum chunk*/

SELECT /*!40001 SQL_NO_CACHE */ `y` FROM `issue_519`.`t` FORCE INDEX(`y`) WHERE ((`y` >= ?)) ORDER BY `y` LIMIT ?, 2 /*next chunk boundary*/

1 2000 2002
2 2003 2005
3 2006 2008
4 2009 2010

",
   "Chunks on left-most --chunk-index column"
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
"--
-- issue_519.t
--

REPLACE INTO `percona`.`checksums` (db, tbl, chunk, chunk_index, lower_boundary, upper_boundary, this_cnt, this_crc) SELECT ?, ?, ?, ?, ?, ?, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `i`, `y`, `t`, CONCAT(ISNULL(`t`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_519`.`t` FORCE INDEX(`y`) WHERE ((`y` >= ?)) AND ((`y` <= ?)) AND (y > 2009) ORDER BY `y` /*checksum chunk*/

SELECT /*!40001 SQL_NO_CACHE */ `y` FROM `issue_519`.`t` FORCE INDEX(`y`) WHERE ((`y` >= ?)) AND (y > 2009) ORDER BY `y` LIMIT ?, 2 /*next chunk boundary*/

1 2010 2010

",
   "Auto-chosen --chunk-index for --where (issue 378)"
);

# If user specifies --chunk-index, then ignore the index MySQL wants to
# use (y in this case) and use the user's index.
$output = output(
   sub { pt_table_checksum::main(@args, qw(--chunk-index PRIMARY),
      "--where", "y > 2009") },
);

is(
   $output,
"--
-- issue_519.t
--

REPLACE INTO `percona`.`checksums` (db, tbl, chunk, chunk_index, lower_boundary, upper_boundary, this_cnt, this_crc) SELECT ?, ?, ?, ?, ?, ?, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `i`, `y`, `t`, CONCAT(ISNULL(`t`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `issue_519`.`t` FORCE INDEX(`PRIMARY`) WHERE ((`i` >= ?)) AND ((`i` <= ?)) AND (y > 2009) ORDER BY `i` /*checksum chunk*/

SELECT /*!40001 SQL_NO_CACHE */ `i` FROM `issue_519`.`t` FORCE INDEX(`PRIMARY`) WHERE ((`i` >= ?)) AND (y > 2009) ORDER BY `i` LIMIT ?, 2 /*next chunk boundary*/

1 11 11

",
   "Explicit --chunk-index overrides MySQL's index for --where"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
