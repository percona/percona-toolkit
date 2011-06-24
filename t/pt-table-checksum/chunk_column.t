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
   plan tests => 5;
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
   sub { mk_table_checksum::main(@args) },
);

is(
   $output,
   $default_output,
   "Chooses chunk column by default"
);

$output = output(
   sub { mk_table_checksum::main(@args, qw(--chunk-column batman)) },
);

is(
   $output,
   $default_output,
   "Chooses chunk column if --chunk-column doesn't exist"
);

$output = output(
   sub { mk_table_checksum::main(@args, qw(--chunk-column t)) },
);

is(
   $output,
   $default_output,
   "Chooses chunk column if --chunk-column isn't chunkable"
);

$output = output(
   sub { mk_table_checksum::main(@args, qw(--chunk-column i --chunk-index y)) },
);

is(
   $output,
   $default_output,
   "Chooses chunk column if it isn't chunkable with --chunk-index",
);

$output = output(
   sub { mk_table_checksum::main(@args, qw(--chunk-column y)) },
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
   "Use --chunk-column"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
