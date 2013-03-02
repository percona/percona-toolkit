#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;
use Data::Dumper;

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use Sandbox;
use OptionParser;
use DSNParser;
use Quoter;
use PerconaTest;
use Cxn;
use VersionParser;

use Percona::XtraDB::Cluster;

my $q   = new Quoter();
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

my $cluster = Percona::XtraDB::Cluster->new();

my $db_flavor = VersionParser->new($master_dbh)->flavor();

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( $db_flavor !~ /XtraDB Cluster/ ) {
   plan skip_all => "PXC-only test";
}

my $o  = new OptionParser(
   description => 'Cxn',
   file        => "$trunk/bin/pt-table-checksum",
);
$o->get_specs("$trunk/bin/pt-table-checksum");
$o->get_opts();

# In 2.1, these tests did not set innodb_lock_wait_timeout because
# it was not a --set-vars default but rather its own option handled
# by/in the tool.  In 2.2, the var is a --set-vars default, which
# means it will cause a warning on 5.0 and 5.1, so we remoe the var
# to remove the warning.
my $set_vars = $o->set_vars();
delete $set_vars->{innodb_lock_wait_timeout};
delete $set_vars->{lock_wait_timeout};
$dp->prop('set-vars', $set_vars);

sub make_cxn {
   my (%args) = @_;
   $o->get_opts();
   return new Cxn(
      OptionParser => $o,
      DSNParser    => $dp,
      %args,
   );
}

local @ARGV = ();
$o->get_opts();

diag("Starting master1");
$sb->start_sandbox(type => "master", server => "master1");

my $master1_cxn = make_cxn( dsn_string => $sb->dsn_for("master1") );
$master1_cxn->connect();

diag("Starting a 1-node PXC");
my $c     = $sb->start_cluster(
   nodes => [qw(node4)],
   env   => q/CLUSTER_NAME="pt_size_1"/
);

my $cxn1 = make_cxn( dsn_string => $c->{node4}->{dsn} );
$cxn1->connect();
ok(
   $cluster->is_cluster_node($cxn1),
   "is_cluster_node works correctly for cluster nodes"
);

diag("Setting node as a slave of master1");
$sb->set_as_slave("node4", "master1");
ok(
   !$cluster->same_cluster($master1_cxn, $cxn1),
   "->same_cluster works for master -> cluster"
);
diag("Restarting the cluster");
diag($sb->stop_sandbox(qw(node4)));
$c     = $sb->start_cluster(
   nodes => [qw(node4)],
   env   => q/CLUSTER_NAME="pt_size_1"/
);
$cxn1 = make_cxn( dsn_string => $c->{node4}->{dsn} );
$cxn1->connect();

diag("Setting master1 as a slave of the node");
$sb->set_as_slave("master1", "node4");
ok(
   !$cluster->same_cluster($cxn1, $master1_cxn),
   "->same_cluster works for cluster -> master"
);

diag("Starting a 2-node cluster");
my $c2 = $sb->start_cluster(
   nodes => [qw(node5 node6)],
   env   => q/CLUSTER_NAME="pt_size_2"/
);

my $cxn2 = make_cxn( dsn_string => $c2->{node5}->{dsn} );
$cxn2->connect();
my $cxn3 = make_cxn( dsn_string => $c2->{node6}->{dsn} );
$cxn3->connect();
ok(
   $cluster->is_cluster_node($cxn2),
   "is_cluster_node correctly finds that this node is part of a cluster"
);

ok(
   !$cluster->same_cluster($cxn1, $cxn2),
   "and same_cluster correctly finds that they don't belong to the same cluster, even when they have the same cluster name"
);

ok(
   $cluster->same_cluster($cxn2, $cxn3),
   "...but does find that they are in the same cluster, even if one is node1"
);

diag("Making the second cluster a slave of the first");
$sb->set_as_slave("node5", "node4");

ok(
   !$cluster->same_cluster($cxn1, $cxn2),
   "...same_cluster works correctly when they are cluster1.node1.master -> cluster2.node1.slave"
);

diag($sb->stop_sandbox(qw(node5 node6)));
diag("Starting a 3-node cluster");
my $c3 = $sb->start_cluster(
   nodes => [qw(node5 node6 node7)],
   env   => q/CLUSTER_NAME="pt_size_3"/
);
$cxn2    = make_cxn( dsn_string => $c3->{node5}->{dsn} );
$cxn2->connect();
$cxn3    = make_cxn( dsn_string => $c3->{node6}->{dsn} );
$cxn3->connect();
my $cxn4 = make_cxn( dsn_string => $c3->{node7}->{dsn} );
$cxn4->connect();

ok(
   !$cluster->same_cluster($cxn1, $cxn2),
   "...same_cluster works correctly when they have different cluster names & the are both gcomm"
);

ok(
   !$cluster->same_cluster($cxn1, $cxn3),
   "same_cluster detects that (cluster1.node1) (cluster2.node2) come from different clusters if they have different cluster_names"
);

ok(
   $cluster->same_cluster($cxn2, $cxn3),
   "sanity check: but still finds that nodes in the same cluster belong together"
);

diag($sb->stop_sandbox(qw(node4 node5 node6 node7)));

diag($sb->stop_sandbox("master1"));

# #############################################################################
# Done.
# #############################################################################
$master_dbh->disconnect() if $master_dbh;
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
