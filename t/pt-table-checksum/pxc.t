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
use Data::Dumper;

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $ip = qr/\Q127.1\E|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $node1 = $sb->get_dbh_for('node1');
my $node2 = $sb->get_dbh_for('node2');
my $node3 = $sb->get_dbh_for('node3');

if ( !$node1 ) {
   plan skip_all => 'Cannot connect to cluster node1';
}
elsif ( !$node2 ) {
   plan skip_all => 'Cannot connect to cluster node2';
}
elsif ( !$node3 ) {
   plan skip_all => 'Cannot connect to cluster node3';
}
elsif ( !$sb->is_cluster_mode ) {
   plan skip_all => "PXC tests";
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
my $node1_dsn = $sb->dsn_for('node1');
my @args      = ($node1_dsn, qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-table-checksum/samples/";

# #############################################################################
# pt-table-checksum v2.1.4 doesn't detect diffs on Percona XtraDB Cluster nodes
# https://bugs.launchpad.net/percona-toolkit/+bug/1062563
# #############################################################################

# #############################################################################
# Check just a cluster
# #############################################################################

# This DSN table has node2 and node3 (12346 and 12347) but not node1 (12345)
# because it was originally created for traditional setups which require only
# slave DSNs, but the DSN table for a PXC setup can/should contain DSNs for
# all nodes so the user can run pxc on any node and find all the others.
$sb->load_file('node1', "$sample/dsn-table.sql");
$node1->do(qq/INSERT INTO dsns.dsns VALUES (1, 1, '$node1_dsn')/);

# First a little test to make sure the tool detects and bails out
# if no other cluster nodes are detected, in which case the user
# probably didn't specifying --recursion-method dsn.
$output = output(
   sub { pt_table_checksum::main(@args) },
   stderr => 1,
);

like(
   $output,
   qr/h=127(?:\Q.0.0\E)?.1,P=12345 is a cluster node but no other nodes/,
   "Dies if no other nodes are found"
);


($output, $exit_status) = full_output(
   sub { pt_table_checksum::main(@args, '--recursion-method', 'none') },
   stderr => 1,
);

ok (
      $output !~ qr/no other nodes or regular replicas were found/i && !$exit_status,
      "checksums even if --recursion-method=none - issue 1373937"
);

for my $args (
      ["using recusion-method=dsn", '--recursion-method', "dsn=$node1_dsn,D=dsns,t=dsns"],
      ["using recursion-method=cluster", '--recursion-method', 'cluster']
   )
{
   my $test = shift @$args;
   $output = output(
      sub { pt_table_checksum::main(@args,
         @$args)
      },
      stderr => 1,
   );

   is(
      PerconaTest::count_checksum_results($output, 'errors'),
      0,
      "No diffs: no errors ($test)"
   );

   is(
      PerconaTest::count_checksum_results($output, 'skipped'),
      0,
      "No diffs: no skips ($test)"
   );

   is(
      PerconaTest::count_checksum_results($output, 'diffs'),
      0,
      "No diffs: no diffs ($test)"
   );
}

# Now really test checksumming a cluster.  To create a diff we have to disable
# the binlog.  Although PXC doesn't need or use the binlog to communicate
# (it has its own broadcast-based protocol implemented via the Galera lib)
# it still respects sql_log_bin, so we can make a change on one node without
# affecting the others.
$sb->load_file('node1', "$sample/a-z.sql");
$node2->do("set sql_log_bin=0");
$node2->do("update test.t set c='zebra' where c='z'");
$node2->do("set sql_log_bin=1");

my ($row) = $node2->selectrow_array("select c from test.t order by c desc limit 1");
is(
   $row,
   "zebra",
   "Node2 is changed"
);

($row) = $node1->selectrow_array("select c from test.t order by c desc limit 1");
is(
   $row,
   "z",
   "Node1 not changed"
);

($row) = $node3->selectrow_array("select c from test.t order by c desc limit 1");
is(
   $row,
   "z",
   "Node3 not changed"
);

sub test_recursion_methods {
   my $same_ids = shift;

   my ($orig_id_1, $orig_id_2, $orig_id_3);
   my ($orig_ia_1, $orig_ia_2, $orig_ia_3);

   if ($same_ids) {
      # save original values
      my $sql = 'SELECT @@server_id';
      ($orig_id_1) = $node1->selectrow_array($sql);
      ($orig_id_2) = $node2->selectrow_array($sql);
      ($orig_id_3) = $node3->selectrow_array($sql);
      # set server_id  value to 1 on all nodes
      $sql = 'SET GLOBAL server_id = 1';
      $node1->do($sql);
      $node2->do($sql);
      $node3->do($sql);

      # since we're testing server id issues, set wsrep_node_incoming_address=AUTO ( https://bugs.launchpad.net/percona-toolkit/+bug/1399789 )  
      # save original values
      $sql = 'SELECT @@wsrep_node_incoming_address';
      ($orig_ia_1) = $node1->selectrow_array($sql);
      ($orig_ia_2) = $node2->selectrow_array($sql);
      ($orig_ia_3) = $node3->selectrow_array($sql);
      # set wsrep_node_incoming_address  value to AUTO on all nodes
      $sql = 'SET GLOBAL wsrep_node_incoming_address = AUTO';
      $node1->do($sql);
      $node2->do($sql);
      $node3->do($sql);
      
   }

   for my $args (
         ["using recusion-method=dsn", '--recursion-method', "dsn=$node1_dsn,D=dsns,t=dsns"],
         ["using recursion-method=cluster", '--recursion-method', 'cluster']
      )
   {
      my $test = shift @$args;
      $test = $same_ids ? $test.' - Nodes with different ids' : $test.' - Nodes with same ids';

      $output = output(
         sub { pt_table_checksum::main(@args,
            @$args)
         },
         stderr => 1,
      );

      is(
         PerconaTest::count_checksum_results($output, 'errors'),
         0,
         "1 diff: no errors ($test)"
      );

      is(
         PerconaTest::count_checksum_results($output, 'skipped'),
         0,
         "1 diff: no skips ($test)"
      );

      is(
         PerconaTest::count_checksum_results($output, 'diffs'),
         1,
         "1 diff: 1 diff ($test)"
      ) or diag($output);

      # 11-17T13:02:54      0      1       26       1       0   0.021 test.t
      like(
         $output,
         qr/^\S+\s+  # ts
            0\s+     # errors
            1\s+     # diffs
            26\s+    # rows
            \d+\s+   # chunks
            0\s+     # skipped
            \S+\s+   # time
            test.t$  # table
         /xm,
         "1 diff: it's in test.t ($test)"
      );
   }

   if ($same_ids) {
      # reset server_id's to original values
      $node1->do("SET GLOBAL server_id = $orig_id_1");
      $node2->do("SET GLOBAL server_id = $orig_id_2");
      $node3->do("SET GLOBAL server_id = $orig_id_3");
      # reset node wsrep_node_incoming_address to original values
      $node1->do("SET GLOBAL wsrep_node_incoming_address = '$orig_ia_1'");
      $node2->do("SET GLOBAL wsrep_node_incoming_address = '$orig_ia_2'");
      $node3->do("SET GLOBAL wsrep_node_incoming_address = '$orig_ia_3'");
   }

}

# test recursion methods
test_recursion_methods(0);

# test recursion methods when all nodes have the same id
test_recursion_methods(1);


# #############################################################################
# cluster, node1 -> slave, run on node1
# #############################################################################

my ($slave_dbh, $slave_dsn) = $sb->start_sandbox(
   server => 'cslave1',
   type   => 'slave',
   master => 'node1',
   env    => q/FORK="pxc" BINLOG_FORMAT="ROW"/,
);

# Add the slave to the DSN table.
$node1->do(qq/INSERT INTO dsns.dsns VALUES (4, 3, '$slave_dsn')/);

# Fix what we changed earlier on node2 so the cluster is consistent.
$node2->do("set sql_log_bin=0");
$node2->do("update test.t set c='z' where c='zebra'");
$node2->do("set sql_log_bin=1");

# Wait for the slave to apply the binlogs from node1 (its master).
# Then change it so it's not consistent.
PerconaTest::wait_for_table($slave_dbh, 'test.t');
$sb->wait_for_slaves(master => 'node1', slave => 'cslave1');
$slave_dbh->do("update test.t set c='zebra' where c='z'");

# Another quick test first: the tool should complain about the slave's
# binlog format but only the slave's, not the cluster nodes:
# https://bugs.launchpad.net/percona-toolkit/+bug/1080385
# Cluster nodes default to ROW format because that's what Galeara
# works best with, even though it doesn't really use binlogs.
for my $args (
      ["using recusion-method=dsn", '--recursion-method', "dsn=$node1_dsn,D=dsns,t=dsns"],
      ["using recursion-method=cluster,hosts", '--recursion-method', 'cluster,hosts']
   )
{
   my $test = shift @$args;

   # Wait for the slave to apply the binlogs from node1 (its master).
   # Then change it so it's not consistent.
   PerconaTest::wait_for_table($slave_dbh, 'test.t');
   $sb->wait_for_slaves(master => 'node1', slave => 'cslave1');
   $slave_dbh->do("update test.t set c='zebra' where c='z'");

   $output = output(
      sub { pt_table_checksum::main(@args,
         @$args)
      },
      stderr => 1,
   );

   like(
      $output,
      qr/replica h=127(?:\Q.0.0\E)?\.1,P=12348 has binlog_format ROW/i,
      "--check-binlog-format warns about slave's binlog format ($test)"
   );
   
   # Now really test that diffs on the slave are detected.
   $output = output(
      sub { pt_table_checksum::main(@args,
         @$args,
         qw(--no-check-binlog-format)),
      },
      stderr => 1,
   );

   is(
      PerconaTest::count_checksum_results($output, 'diffs'),
      1,
      "Detects diffs on slave of cluster node1 ($test)"
   ) or diag($output);

}

$slave_dbh->disconnect;
$sb->stop_sandbox('cslave1');

# #############################################################################
# cluster, node2 -> slave, run on node1
#
# Does not work because we only set binglog_format=STATEMENT on node1 which
# does not affect other nodes, so node2 gets checksum queries in STATEMENT
# format, executes them, but then logs the results in ROW format (since ROW
# format is the default for cluster nodes) which doesn't work on the slave
# (i.e. the slave doesn't execute the query).  So any diffs on the slave are
# not detected.
# #############################################################################

($slave_dbh, $slave_dsn) = $sb->start_sandbox(
   server => 'cslave1',
   type   => 'slave',
   master => 'node2',
   env    => q/FORK="pxc" BINLOG_FORMAT="ROW"/,
);

# Wait for the slave to apply the binlogs from node2 (its master).
# Then change it so it's not consistent.
PerconaTest::wait_for_table($slave_dbh, 'test.t');
$sb->wait_for_slaves(master => 'node1', slave => 'cslave1');
$slave_dbh->do("update test.t set c='zebra' where c='z'");

($row) = $slave_dbh->selectrow_array("select c from test.t order by c desc limit 1");
is(
   $row,
   "zebra",
   "Slave is changed"
);

for my $args (
      ["using recusion-method=dsn", '--recursion-method', "dsn=$node1_dsn,D=dsns,t=dsns"],
      ["using recursion-method=cluster,hosts", '--recursion-method', 'cluster,hosts']
   )
{
   my $test = shift @$args;

   $output = output(
      sub { pt_table_checksum::main(@args,
         @$args,
         qw(--no-check-binlog-format -d test)),
      },
      stderr => 1,
   );

   is(
      PerconaTest::count_checksum_results($output, 'diffs'),
      0,
      "Limitation: does not detect diffs on slave of cluster node2 ($test)"
   ) or diag($output);
}
   
$slave_dbh->disconnect;
$sb->stop_sandbox('cslave1');

# Restore the original DSN table.
$node1->do(qq/DELETE FROM dsns.dsns WHERE id=4/);

# #############################################################################
# master -> node1 in cluster, run on master
# #############################################################################

# CAREFUL: The master and the cluster are different, so don't do stuff
# on the master that will conflict with stuff already done on the cluster.
# And since we're using RBR, we have to do a lot of stuff on the master
# again, manually, because REPLACE and INSERT IGNORE don't work in RBR
# like they do SBR.

my ($master_dbh, $master_dsn) = $sb->start_sandbox(
   server => 'cmaster',
   type   => 'master',
   env    => q/FORK="pxc" BINLOG_FORMAT="ROW"/,
);

# Since master is new, node1 shouldn't have binlog to replay.
$sb->set_as_slave('node1', 'cmaster');

# We have to load a-z-cluster.sql else the pk id won'ts match because nodes use
# auto-inc offsets but the master doesn't.
$sb->load_file('cmaster', "$sample/a-z-cluster.sql", undef, no_wait => 1);

# Do this stuff manually and only on the master because node1/the cluster
# already has it, and due to RBR, we can't do it other ways.
$master_dbh->do("SET sql_log_bin=0");

# This DSN table does not include 12345 (node1/slave) intentionally,
# so a later test can auto-find 12345 then warn "Diffs will only be
# detected if the cluster is consistent with h=127.1,P=12345...".
$master_dbh->do("CREATE DATABASE dsns");
$master_dbh->do("CREATE TABLE dsns.dsns (
  id int auto_increment primary key,
  parent_id int default null,
  dsn varchar(255) not null
)");
$master_dbh->do("INSERT INTO dsns.dsns VALUES
  (2, 1,    'h=127.1,P=12346,u=msandbox,p=msandbox'),
  (3, 2,    'h=127.1,P=12347,u=msandbox,p=msandbox')");

$master_dbh->do("INSERT INTO percona_test.sentinel (id, ping) VALUES (1, '')");
$master_dbh->do("SET sql_log_bin=1");

$sb->wait_for_slaves(master => 'cmaster', slave => 'node1');

# Notice: no --recursion-method=dsn yet.  Since node1 is a traditional slave
# of the master, ptc should auto-detect it, which we'll test later by making
# the slave differ.
$output = output(
   sub { pt_table_checksum::main($master_dsn,
      qw(-d test))
   },
   stderr => 1,
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "master->cluster no diffs: no errors"
);

is(
   PerconaTest::count_checksum_results($output, 'skipped'),
   0,
   "master->cluster no diffs: no skips"
);

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   0,
   "master->cluster no diffs: no diffs"
) or diag($output);

# Make a diff on node1.  If ptc is really auto-detecting node1, then it
# should report this diff.
$node1->do("set sql_log_bin=0");
$node1->do("update test.t set c='zebra' where c='z'");
$node1->do("set sql_log_bin=1");

$output = output(
   sub { pt_table_checksum::main($master_dsn,
      qw(-d test))
   },
   stderr => 1,
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "master->cluster 1 diff: no errors"
);

is(
   PerconaTest::count_checksum_results($output, 'skipped'),
   0,
   "master->cluster 1 diff: no skips"
);

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   1,
   "master->cluster 1 diff: 1 diff"
) or diag($output);

# 11-17T13:02:54      0      1       26       1       0   0.021 test.t
like(
   $output,
   qr/^\S+\s+  # ts
      0\s+     # errors
      1\s+     # diffs
      26\s+    # rows
      \d+\s+   # chunks
      0\s+     # skipped
      \S+\s+   # time
      test.t$  # table
   /xm,
   "master->cluster 1 diff: it's in test.t"
);

# Use the DSN table to check for diffs on node2 and node3.  This works
# because the diff is on node1 and node1 is the direct slave of the master,
# so the checksum query will replicate from the master in STATEMENT format,
# node1 will execute it, find the diff, then broadcast that result to all
# other nodes. -- Remember: the DSN table on the master has node2 and node3.
$output = output(
   sub { pt_table_checksum::main($master_dsn,
      '--recursion-method', "dsn=$master_dsn,D=dsns,t=dsns",
      qw(-d test))
   },
   stderr => 1,
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "...check other nodes: no errors"
);

is(
   PerconaTest::count_checksum_results($output, 'skipped'),
   0,
   "...check other nodes: no skips"
);

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   1,
   "...check other nodes: 1 diff"
) or diag($output);

# 11-17T13:02:54      0      1       26       1       0   0.021 test.t
like(
   $output,
   qr/^\S+\s+  # ts
      0\s+     # errors
      1\s+     # diffs
      26\s+    # rows
      \d+\s+   # chunks
      0\s+     # skipped
      \S+\s+   # time
      test.t$  # table
   /xm,
   "...check other nodes: it's in test.t"
);

like(
   $output,
   qr/the direct replica of h=$ip,P=12349 was not found or specified/,
   "Warns that direct replica of the master isn't found or specified",
);

# Use the other DSN table with all three nodes.  Now the tool should
# give a more specific warning than that ^.
# Originally, these tested a dsn table with all nodes; now we hijack
# those tests to also try the autodetection
for my $args (
      ["using recusion-method=dsn", '--recursion-method', "dsn=$node1_dsn,D=dsns,t=dsns"],
      ["using recursion-method=cluster,hosts", '--recursion-method', 'cluster,hosts']
   )
{
   my $test = shift @$args;

   # Make a diff on node1.  If ptc is really auto-detecting node1, then it
   # should report this diff.
   $node1->do("set sql_log_bin=0");
   $node1->do("update test.t set c='zebra' where c='z'");
   $node1->do("set sql_log_bin=1");
   
   $output = output(
      sub { pt_table_checksum::main($master_dsn,
         @$args,
         qw(-d test))
      },
      stderr => 1,
   );

   is(
      PerconaTest::count_checksum_results($output, 'diffs'),
      1,
      "...check all nodes: 1 diff ($test)"
   ) or diag($output);

   # 11-17T13:02:54      0      1       26       1       0   0.021 test.t
   like(
      $output,
      qr/^\S+\s+  # ts
         0\s+     # errors
         1\s+     # diffs
         26\s+    # rows
         \d+\s+   # chunks
         0\s+     # skipped
         \S+\s+   # time
         test.t$  # table
      /xm,
      "...check all nodes: it's in test.t ($test)"
   );

   like(
      $output,
      qr/Diffs will only be detected if the cluster is consistent with h=$ip,P=12345 because h=$ip,P=12349/,
      "Warns that diffs only detected if cluster consistent with direct replica ($test)",
   );

   # Restore node1 so the cluster is consistent, but then make node2 differ.
   # ptc should NOT detect this diff because the checksum query will replicate
   # to node1, node1 isn't different, so it broadcasts the result in ROW format
   # that all is ok, which node2 gets and thus false reports.  This is why
   # those ^ warnings exist.
   $node1->do("set sql_log_bin=0");
   $node1->do("update test.t set c='z' where c='zebra'");
   $node1->do("set sql_log_bin=1");

   $node2->do("set sql_log_bin=0");
   $node2->do("update test.t set c='zebra' where c='z'");
   $node2->do("set sql_log_bin=1");

   ($row) = $node2->selectrow_array("select c from test.t order by c desc limit 1");
   is(
      $row,
      "zebra",
      "Node2 is changed again ($test)"
   );

   ($row) = $node1->selectrow_array("select c from test.t order by c desc limit 1");
   is(
      $row,
      "z",
      "Node1 not changed again ($test)"
   );

   ($row) = $node3->selectrow_array("select c from test.t order by c desc limit 1");
   is(
      $row,
      "z",
      "Node3 not changed again ($test)"
   );

   # the other DSN table with all three nodes, but it won't matter because
   # node1 is going to broadcast the false-positive that there are no diffs.
   $output = output(
      sub { pt_table_checksum::main($master_dsn,
         @$args,
         qw(-d test))
      },
      stderr => 1,
   );

   is(
      PerconaTest::count_checksum_results($output, 'diffs'),
      0,
      "Limitation: diff not on direct replica not detected ($test)"
   ) or diag($output);

}

# ###########################################################################
# Be sure to stop the slave on node1, else further test will die with:
# Failed to execute -e "change master to master_host='127.0.0.1',
# master_user='msandbox', master_password='msandbox', master_port=12349"
# on node1: ERROR 1198 (HY000) at line 1: This operation cannot be performed
# with a running slave; run STOP SLAVE first
# ###########################################################################
$master_dbh->disconnect;
$sb->stop_sandbox('cmaster');
$node1->do("STOP SLAVE");
$node1->do("RESET SLAVE");

# #############################################################################
# cluster -> cluster
#
# This is not supported.  The link between the two clusters is probably
# a traditional MySQL replication setup in ROW format, so any checksum
# results will be lost across it.
# #############################################################################

my $c = $sb->start_cluster(
   nodes => [qw(node4 node5 node6)],
   env   => q/CLUSTER_NAME="cluster2"/,
);

# Load the same db just in case this does work (it shouldn't), then there
# will be normal results instead of an error because the db is missing.
$sb->load_file('node4', "$sample/a-z.sql");

# Add node4 in the cluster2 to the DSN table.
$node1->do(qq/INSERT INTO dsns.dsns VALUES (5, null, '$c->{node4}->{dsn}')/);

$output = output(
   sub { pt_table_checksum::main(@args,
      '--recursion-method', "dsn=$node1_dsn,D=dsns,t=dsns",
      qw(-d test))
   },
   stderr => 1,
);

like(
   $output,
   qr/h=127(?:\Q.0.0\E)?.1,P=12345 is in cluster pt_sandbox_cluster/,
   "Detects that node1 is in pt_sandbox_cluster"
);

like(
   $output,
   qr/h=127(?:\Q.0.0\E)?.1,P=2900 is in cluster cluster2/,
   "Detects that node4 is in cluster2"
);

unlike(
   $output,
   qr/test/,
   "Different clusters, no results"
);
   
$sb->stop_sandbox(qw(node4 node5 node6));

# Restore the DSN table in case there are more tests.
$node1->do(qq/DELETE FROM dsns.dsns WHERE id=5/);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($node1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
