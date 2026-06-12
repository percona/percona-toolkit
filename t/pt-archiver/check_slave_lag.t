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
require "$trunk/bin/pt-archiver";

my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh  = $sb->get_dbh_for('source');
my $dbh2 = $sb->get_dbh_for('replica1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
elsif ( $sb->is_cluster_mode ) {
   plan skip_all => 'Not for PXC',
}
elsif ( $sandbox_version ge '5.6' ) {
   plan skip_all => 'Replica trick does not work on MySQL 5.6+';
}

my $output;
my $sql;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

# #############################################################################
# Issue 758: Make mk-archiver wait for a replica
# #############################################################################

$sb->load_file('source', 't/pt-archiver/samples/issue_758.sql');

is_deeply(
   $dbh->selectall_arrayref('select * from issue_758.t'),
   [[1],[2]],
   'Table not purged yet (issue 758)'
);

# Once this goes through repl, the replica will sleep causing
# seconds behind source to increase > 0.
system('/tmp/12345/use -e "insert into issue_758.t select sleep(3)"');

# Replica seems to be lagging now so the first row should get purged
# immediately, then the script should wait about 2 seconds until
# replica lag is gone.
system("$cmd --source F=$cnf,D=issue_758,t=t --purge --where 'i>0' --check-${replica_name}-lag h=127.1,P=12346,u=msandbox,p=msandbox &");

sleep 1;
is_deeply(
   $dbh2->selectall_arrayref('select * from issue_758.t'),
   [[1],[2]],
   'No changes on replica yet (issue 758)'
);

is_deeply(
   $dbh->selectall_arrayref('select * from issue_758.t'),
   [[0],[2]],
   'First row purged (issue 758)'
);

# The script it waiting for replica lag so no more rows should be purged yet.
sleep 1;
is_deeply(
   $dbh->selectall_arrayref('select * from issue_758.t'),
   [[0],[2]],
   'Still only first row purged (issue 758)'
);

# After this sleep the replica should have executed the INSERT SELECT,
# which returns 0, and the 2 purge/delete statments from above.
sleep 3;
is_deeply(
   $dbh->selectall_arrayref('select * from issue_758.t'),
   [[0]],
   'Final table state on source (issue 758)'
);

is_deeply(
   $dbh2->selectall_arrayref('select * from issue_758.t'),
   [[0]],
   'Final table state on replica (issue 758)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
