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
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 1;
}

my $output;
my $res;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/checksum_tbl.sql');
$sb->load_file('master', 't/pt-table-checksum/samples/issue_94.sql');
sleep 1;

# #############################################################################
# Issue 51: --wait option prevents data from being inserted
# #############################################################################

# This test relies on table issue_94 created somewhere above, which has
# something like:
# mysql> select * from issue_94;
# +----+----+---------+
# | a  | b  | c       |
# +----+----+---------+
# |  1 |  2 | apple   | 
# |  3 |  4 | banana  | 
# |  5 |  6 | kiwi    | 
# |  7 |  8 | orange  | 
# |  9 | 10 | grape   | 
# | 11 | 12 | coconut | 
# +----+----+---------+

$master_dbh->do('DELETE FROM test.checksum');
# Give it something to think about. 
$slave_dbh->do('DELETE FROM test.issue_94 WHERE a > 5');
`$cmd --replicate=test.checksum --algorithm=BIT_XOR --databases test --tables issue_94 --chunk-size 500000 --wait 900`;
my $row = $master_dbh->selectrow_arrayref("SELECT * FROM test.checksum");
is(
   $row->[1],
   'issue_94',
   '--wait does not prevent update to --replicate tbl (issue 51)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
