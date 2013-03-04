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
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $output;
my $row;

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/issue_47.sql');

# #############################################################################
# Issue 47: TableChunker::range_num broken for very large bigint
# #############################################################################

# pt-table-checksum 2.0 doesn't use TableChunker; it uses NibbleIterator.
# But we'll test this anyway to make sure that NibbleIterator can't handle
# very larger integers.

$output = pt_table_checksum::main(@args, qw(-t test.issue_47),
      qw(--chunk-time 0 --chunk-size 3 --quiet));
is(
   $output,
   "0",
   "No error nibbling very large int"
);

$row = $master_dbh->selectall_arrayref("select lower_boundary, upper_boundary from percona.checksums where db='test' and tbl='issue_47' order by chunk");
is_deeply(
   $row,
   [
      [ '1',        '300'                  ],
      [ '1000',     '2220293'              ],
      [ '65553510', '18446744073709551615' ],
      [ undef,      '1'                    ], # lower oob
      [ '18446744073709551615',      undef ], # upper oob
   ],
   "Uses very large int as chunk boundary"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
