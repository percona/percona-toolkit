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

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/issue_122.sql');

# #############################################################################
# Issue 122: mk-table-checksum doesn't --save-since correctly on empty tables
# #############################################################################

`$cmd --arg-table test.argtable --save-since -t test.issue_122 --chunk-size 2`;
is_deeply(
   $master_dbh->selectall_arrayref("SELECT since FROM test.argtable WHERE db='test' AND tbl='issue_122'"),
   [[undef]],
   'Numeric since is not saved when table is empty'
);

$master_dbh->do("INSERT INTO test.issue_122 VALUES (null,'a'),(null,'b')");
`$cmd --arg-table test.argtable --save-since -t test.issue_122 --chunk-size 2`;
is_deeply(
   $master_dbh->selectall_arrayref("SELECT since FROM test.argtable WHERE db='test' AND tbl='issue_122'"),
   [[2]],
   'Numeric since is saved when table is not empty'
);

# Test non-empty table that is chunkable with a temporal --since and
# --save-since to make sure that the current ts gets saved and not the maxval.
$master_dbh->do('UPDATE test.argtable SET since = "current_date - interval 3 day" WHERE db = "test" AND tbl = "issue_122"');
`$cmd --arg-table test.argtable --save-since -t test.issue_122 --chunk-size 2`;
$output = $master_dbh->selectall_arrayref("SELECT since FROM test.argtable WHERE db='test' AND tbl='issue_122'")->[0]->[0];
like(
   $output,
   qr/^\d{4}-\d{2}-\d{2}(?:.[0-9:]+)?/,
   'Temporal since is saved when temporal since is given'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
