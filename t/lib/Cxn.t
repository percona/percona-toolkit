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

use Sandbox;
use OptionParser;
use DSNParser;
use Quoter;
use PerconaTest;
use Cxn;
use VersionParser;

my $q   = new Quoter();
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

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

sub test_var_val {
   my ($dbh, $var, $val, %args) = @_;

   my @row;
   if ( !$args{user_var} ) { 
      my $sql = "SHOW " . ($args{global} ? "GLOBAL" : "SESSION " )
              . "VARIABLES LIKE '$var'";
      @row = $dbh->selectrow_array($sql);
   }
   else {
      my $sql = "SELECT $var, $var";
      @row = $dbh->selectrow_array($sql);
   }

   if ( $args{ne} ) {
      ok(
         $row[1] ne $val,
         $args{test} || "$var != $val"
      );
   }
   else {
      is(
         $row[1],
         $val,
         $args{test} || "$var = $val"
      );
   }
}

# The default wait_timeout should not be 10000.  Verify this so when
# Cxn sets it, it's not coincidentally 10000, it was actually set.
test_var_val(
   $master_dbh,
   'wait_timeout',
   '10000',
   ne   =>1,
   test => 'Default wait_timeout',
);

my $set_calls = 0;
my $cxn = make_cxn(
   dsn_string => 'h=127.1,P=12345,u=msandbox,p=msandbox',
   set        => sub {
      my ($dbh) = @_;
      $set_calls++;
      $dbh->do("SET \@a := \@a + 1");
   },
);

ok(
   !$cxn->dbh(),
   "New Cxn, dbh not connected yet"
);

is(
   $cxn->name(),
   'h=127.1,P=12345',
   'name() uses DSN if not connected'
);

$cxn->connect();
ok(
   $cxn->dbh()->ping(),
   "cxn->connect()"
);

my ($row) = $cxn->dbh()->selectrow_hashref('SHOW MASTER STATUS');
ok(
   exists $row->{binlog_ignore_db},
   "FetchHashKeyName = NAME_lc",
) or diag(Dumper($row));

test_var_val(
   $cxn->dbh(),
   'wait_timeout',
   '10000',
   test => 'Sets --set-vars',
);

is(
   $set_calls,
   1,
   'Calls set callback'
);

$cxn->dbh()->do("SET \@a := 1");
test_var_val(
   $cxn->dbh(),
   '@a',
   '1',
   user_var => 1,
);

my $first_dbh = $cxn->dbh();
$cxn->connect();
my $second_dbh = $cxn->dbh();

is(
   $first_dbh,
   $second_dbh,
   "Doesn't reconnect the same dbh"
);

test_var_val(
   $cxn->dbh(),
   '@a',
   '1',
   user_var => 1,
   test     => "Doesn't re-set the vars",
);

# Reconnect.
$cxn->dbh()->disconnect();
$cxn->connect();

($row) = $cxn->dbh()->selectrow_hashref('SHOW MASTER STATUS');
ok(
   exists $row->{binlog_ignore_db},
   "Reconnect FetchHashKeyName = NAME_lc",
) or diag(Dumper($row));

test_var_val(
   $cxn->dbh(),
   'wait_timeout',
   '10000',
   test => 'Reconnect sets --set-vars',
);

is(
   $set_calls,
   2,
   'Reconnect calls set callback'
);

test_var_val(
   $cxn->dbh(),
   '@a',
   undef,
   user_var => 1,
   test    => 'Reconnect is a new connection',
);

is_deeply(
   $cxn->dsn(),
   {
      h => '127.1',
      P => '12345',
      u => 'msandbox',
      p => 'msandbox',
      A => undef,
      F => undef,
      S => undef,
      D => undef,
      t => undef,
   },
   "cxn->dsn()"
);

my ($hostname) = $master_dbh->selectrow_array('select @@hostname');
is(
   $cxn->name(),
   $hostname,
   'name() uses @@hostname'
);

# ############################################################################
# Default cxn, should be equivalent to 'h=localhost'.
# ############################################################################
my $default_cxn = make_cxn();
is_deeply(
   $default_cxn->dsn(),
   {
      h => 'localhost',
      P => undef,
      u => undef,
      p => undef,
      A => undef,
      F => undef,
      S => undef,
      D => undef,
      t => undef,
   },
   "Defaults to h=localhost"
);

# But now test if it will inherit just a few standard connection options.
@ARGV = qw(--port 12345);
$default_cxn = make_cxn();
is_deeply(
   $default_cxn->dsn(),
   {
      h => 'localhost',
      P => '12345',
      u => undef,
      p => undef,
      A => undef,
      F => undef,
      S => undef,
      D => undef,
      t => undef,
   },
   "Default cxn inherits default connection options"
);

@ARGV = ();
$o->get_opts();

diag("Starting master1");
$sb->start_sandbox("master", "master1");

$cxn = make_cxn( dsn_string => $sb->dsn_for("master1") );
$cxn->connect();
ok(
   !$cxn->is_cluster_node(),
   "is_cluster_node works correctly for non-nodes"
);

my $db_flavor = VersionParser->new($master_dbh)->flavor();
SKIP: {
   skip "PXC-only test", 17
      unless $db_flavor =~ /XtraDB Cluster/;

   diag("Starting a 1-node PXC");
   my ($node)     = $sb->start_cluster(cluster_size => 1);

   my $cxn1 = make_cxn( dsn_string => $sb->dsn_for($node) );
   $cxn1->connect();
   ok(
      $cxn1->is_cluster_node(),
      "is_cluster_node works correctly for cluster nodes"
   );

   ok(
      !$cxn->is_master_of($cxn1),
      "->is_master_of works correctly for a server unrelated to a cluster"
   );

   diag("Setting node as a slave of master1");
   $sb->set_as_slave($node, "master1");
   ok(
      $cxn->is_master_of($cxn1),
      "->is_master_of works correctly for master -> cluster"
   );
   ok(
      !$cxn1->is_master_of($cxn),
      "...and the inverse returns the expected result"
   );
   ok(
      !$cxn->same_cluster($cxn1),
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
      $cxn1->is_master_of($cxn),
      "->is_master_of works correctly for cluster -> master"
   );
   ok(
      !$cxn->is_master_of($cxn1),
      "...and the inverse returns the expected result"
   );
   
   ok(
      !$cxn1->same_cluster($cxn),
      "->same_cluster works for cluster -> master"
   );
   
   diag("Starting a 2-node PXC");
   my ($node2, $node3) = $sb->start_cluster(cluster_size => 2);
   
   my $cxn2 = make_cxn( dsn_string => $sb->dsn_for($node2) );
   $cxn2->connect();
   my $cxn3 = make_cxn( dsn_string => $sb->dsn_for($node3) );
   $cxn3->connect();
   ok(
      $cxn2->is_cluster_node(),
      "is_cluster_node correctly finds that this node is part of a cluster"
   );
   
   ok(
      !$cxn1->same_cluster($cxn2),
      "and same_cluster correctly finds that they don't belong to the same cluster, even when they have the same cluster name"
   );
   
   ok(
      $cxn2->same_cluster($cxn3),
      "...but does find that they are in the same cluster, even if one is node1"
   );
   
   TODO: {
      local $::TODO = "Should detected that (cluster1.node1) (cluster2.node2) come from different clusters, but doesn't";
      ok(
         !$cxn1->same_cluster($cxn3),
         "...same_cluster works correctly when they have the same cluster names"
      );
   }
   
   diag("Making the second cluster a slave of the first");
   $sb->set_as_slave($node2, $node);
   ok($cxn1->is_master_of($cxn2), "is_master_of works");

   ok(
      !$cxn1->same_cluster($cxn2),
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
      !$cxn1->same_cluster($cxn2),
      "...same_cluster works correctly when they have different cluster names & the are both gcomm"
   );
   
   ok(
      !$cxn1->same_cluster($cxn3),
      "same_cluster detects that (cluster1.node1) (cluster2.node2) come from different clusters if they have different cluster_names"
   );
   
   ok(
      $cxn2->same_cluster($cxn3),
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
