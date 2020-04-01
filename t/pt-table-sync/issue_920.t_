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
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

plan skip_all => 'Pending solution';

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 4;
}

# #############################################################################
# Issue 920: mk-table-sync fails silently with non-primary UNIQUE KEY
# conflict when using Chunk or Nibble.
# #############################################################################
$sb->wipe_clean($dbh);
$sb->load_file('master', 't/pt-table-sync/samples/issue_920.sql');

pt_table_sync::main(qw(--execute -F /tmp/12345/my.sandbox.cnf),
   'D=issue_920,t=PK_UK_test', 'D=issue_920,t=PK_UK_test_2');

is_deeply(
   $dbh->selectall_arrayref('select * from issue_920.PK_UK_test_2 order by id'),
   [[1,200],[2,100]],
   'Synced 2nd table'
);

$dbh->do('update issue_920.PK_UK_test set id2 = 2 WHERE id = 2');
$dbh->do('update issue_920.PK_UK_test set id2 = 100 WHERE id = 1');
$dbh->do('update issue_920.PK_UK_test set id2 = 200 WHERE id = 2');

is_deeply(
   $dbh->selectall_arrayref('select * from issue_920.PK_UK_test order by id'),
   [[1,100],[2,200]],
   'Flipped 1st table'
);

pt_table_sync::main(qw(--execute -F /tmp/12345/my.sandbox.cnf),
   'D=issue_920,t=PK_UK_test', 'D=issue_920,t=PK_UK_test_2');


is_deeply(
   $dbh->selectall_arrayref('select * from issue_920.PK_UK_test_2 order by id'),
   [[1,100],[2,200]],
   'Flipped 2nd table'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
