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

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $o  = new OptionParser(description => 'Cxn');
$o->get_specs("$trunk/bin/pt-table-checksum");
$o->get_opts();
$dp->prop('set-vars', $o->get('set-vars'));

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
$sb->start_sandbox("master", "master1");

my ($master_cxn, $slave1_cxn, $master1_cxn)
   = map {
         my $cxn = make_cxn( dsn_string => $sb->dsn_for($_) );
         $cxn->connect();
         $cxn;
   } qw( master slave1 master1 );

for my $cxn ( $master_cxn, $slave1_cxn, $master1_cxn ) {
   ok(
      !$cluster->is_cluster_node($cxn),
      "is_cluster_node works correctly for non-nodes " . $cxn->name
   );
}

ok($cluster->is_master_of($master_cxn, $slave1_cxn), "is_master_of(master, slave1) is true");
ok(!$cluster->is_master_of($slave1_cxn, $master_cxn), "is_master_of(slave1, master) is false");

my $db_flavor = VersionParser->new($master_dbh)->flavor();
SKIP: {
   skip "PXC-only test", 17
      unless $db_flavor =~ /XtraDB Cluster/;

   diag("Starting a 1-node PXC");
   my ($node)     = $sb->start_cluster(cluster_size => 1);

   my $cxn1 = make_cxn( dsn_string => $sb->dsn_for($node) );
   $cxn1->connect();
   ok(
      $cluster->is_cluster_node($cxn1),
      "is_cluster_node works correctly for cluster nodes"
   );

   ok(
      !$cluster->is_master_of($master1_cxn, $cxn1),
      "->is_master_of works correctly for a server unrelated to a cluster"
   );

   diag("Setting node as a slave of master1");
   $sb->set_as_slave($node, "master1");
   ok(
      $cluster->is_master_of($master1_cxn, $cxn1),
      "->is_master_of works correctly for master -> cluster"
   );
   ok(
      !$cluster->is_master_of($cxn1, $master1_cxn),
      "...and the inverse returns the expected result"
   );
   ok(
      !$cluster->same_cluster($master1_cxn, $cxn1),
      "->same_cluster works for master -> cluster"
   );
   diag("Restarting the cluster");
   diag($sb->stop_sandbox($node));
   ($node) = $sb->start_cluster(cluster_size => 1);
   $cxn1 = make_cxn( dsn_string => $sb->dsn_for($node) );
   $cxn1->connect();

   diag("Setting master1 as a slave of the node");
   $sb->set_as_slave("master1", $node);
   ok(
      $cluster->is_master_of($cxn1, $master1_cxn),
      "->is_master_of works correctly for cluster -> master"
   );
   ok(
      !$cluster->is_master_of($master1_cxn, $cxn1),
      "...and the inverse returns the expected result"
   );

   ok(
      !$cluster->same_cluster($cxn1, $master1_cxn),
      "->same_cluster works for cluster -> master"
   );

   diag("Starting a 2-node PXC");
   my ($node2, $node3) = $sb->start_cluster(cluster_size => 2);

   my $cxn2 = make_cxn( dsn_string => $sb->dsn_for($node2) );
   $cxn2->connect();
   my $cxn3 = make_cxn( dsn_string => $sb->dsn_for($node3) );
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

   TODO: {
      local $::TODO = "Should detected that (cluster1.node1) (cluster2.node2) come from different clusters, but doesn't";
      ok(
         !$cluster->same_cluster($cxn1, $cxn3),
         "...same_cluster works correctly when they have the same cluster names"
      );
   }

   diag("Making the second cluster a slave of the first");
   $sb->set_as_slave($node2, $node);
   ok($cluster->is_master_of($cxn1, $cxn2), "is_master_of(cluster1, cluster2) works");

   ok(
      !$cluster->same_cluster($cxn1, $cxn2),
      "...same_cluster works correctly when they are cluster1.node1.master -> cluster2.node1.slave"
   );

   diag($sb->stop_sandbox($node2, $node3));
   diag("Starting a 3-node cluster");
   my $node4;
   ($node2, $node3, $node4)
      = $sb->start_cluster(
         cluster_size => 3,
         cluster_name => "pt_cxn_test",
      );
   $cxn2    = make_cxn( dsn_string => $sb->dsn_for($node2) );
   $cxn2->connect();
   $cxn3    = make_cxn( dsn_string => $sb->dsn_for($node3) );
   $cxn3->connect();
   my $cxn4 = make_cxn( dsn_string => $sb->dsn_for($node4) );
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

   diag($sb->stop_sandbox($node, $node2, $node3, $node4));
}

diag($sb->stop_sandbox("master1"));

# #############################################################################
# Done.
# #############################################################################
$master_dbh->disconnect() if $master_dbh;
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
