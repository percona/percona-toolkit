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

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use Data::Dumper;
use PerconaTest;
use Sandbox;

# Fix @INC because pt-table-checksum uses subclass OobNibbleIterator.
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave2_dbh = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3));
my $output;
my $exit_status;
my $sample  = "t/pt-table-checksum/samples/";

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/995274
# Can't use an undefined value as an ARRAY reference at pt-table-checksum
# line 2206
# ############################################################################
$sb->load_file('master', "$sample/undef-arrayref-bug-995274.sql");

# Must chunk the table so an index is used.
$output = output(
   sub { $exit_status = pt_table_checksum::main(@args,
      qw(-d test --chunk-size 100)) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Bug 995274 (undef array): zero exit status"
) or diag($output);

cmp_ok(
   PerconaTest::count_checksum_results($output, 'rows'),
   '>',
   1,
   "Bug 995274 (undef array): checksummed rows"
);


# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/987393
# Empy tables cause "undefined value as an ARRAY" errors
# #############################################################################
$master_dbh->do("DROP DATABASE IF EXISTS percona");  # clear old checksums
$sb->load_file('master', "$sample/empty-table-bug-987393.sql");

$output = output(
   sub { $exit_status = pt_table_checksum::main(
      @args, qw(-d test --chunk-size-limit 0)) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Bug 987393 (empty table): zero exit status"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Bug 987393 (empty table): no errors"
);

my $rows = $master_dbh->selectall_arrayref("SELECT db, tbl, chunk, master_crc, master_cnt FROM percona.checksums ORDER BY db, tbl, chunk");
is_deeply(
   $rows,
   [
      ['test', 'test_empty', '1', '0',        '0'],  # empty
      ['test', 'test_full',  '1', 'ac967054', '1'],  # row
   ],
   "Bug 987393 (empty table): checksums"
) or print STDERR Dumper($rows);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/919499
# MySQL error 1592 with MySQL 5.5.18+ and Perl 5.8
# #############################################################################
$output = output(
   sub {
      print `$trunk/bin/pt-table-checksum $master_dsn -t sakila.country 2>&1`;
   }
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Bug 987393 (Perl 5.8 scoping): no errors"
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   109,
   "Bug 987393 (Perl 5.8 scoping): checksummed table"
);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1030031
# pt-table-checksum reports wrong number of DIFFS
# #############################################################################
$sb->load_file('master', "$sample/a-z.sql");
$sb->wait_for_slaves();

# Create 2 diffs on slave1 and 1 diff on slave2.
$slave1_dbh->do("UPDATE test.t SET c='' WHERE id=5");  # diff on slave1 & 2
$slave1_dbh->do("SET SQL_LOG_BIN=0");
$slave1_dbh->do("UPDATE test.t SET c='' WHERE id=20"); # diff only on slave1

# Restore sql_log_bin on slave1 in case later tests use it.
$slave1_dbh->do("SET SQL_LOG_BIN=1");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t test.t --chunk-size 10)) },
);

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   2,
   "Bug 1030031 (wrong DIFFS): 2 diffs"
);

# Restore slave2, but then give it 1 diff that's not the same chunk#
# as slave1, so there's 3 unique chunk that differ.
$slave2_dbh->do("UPDATE test.t SET c='e' WHERE id=5");
$slave2_dbh->do("UPDATE test.t SET c='' WHERE id=26");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t test.t --chunk-size 10)) },
);

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   3,
   "Bug 1030031 (wrong DIFFS): 3 diffs"
);

# #############################################################################
# pt-table-checksum can crash with --columns if none match
# https://bugs.launchpad.net/percona-toolkit/+bug/1016131
# #############################################################################

($output) = full_output(
   sub { pt_table_checksum::main(@args, '--tables', 'mysql.user,mysql.host',
                                 '--columns', 'some_fale_column') },
);

like(
   $output,
   qr/\QSkipping table mysql.user because all columns are excluded by --columns or --ignore-columns/,
   "Bug 1016131: ptc should skip tables where all columns are excluded"
);

# #############################################################################
# pt-table-checksum v2.1.4 doesn't detect diffs on Percona XtraDB Cluster nodes
# https://bugs.launchpad.net/percona-toolkit/+bug/1062563
# #############################################################################
use File::Spec::Functions;

my $db_flavor = VersionParser->new($master_dbh)->flavor();
SKIP: {
   skip "PXC-only tests", 8
      unless $db_flavor =~ /XtraDB Cluster/;

   diag("Creating a 5-node PXC cluster...");
   my @nodes      = $sb->start_cluster(cluster_size => 5);
   diag("Nodes: ", Dumper( { map { $_ => $sb->port_for($_) } @nodes } ));

   my $node2      = $nodes[1];
   my $node2_dbh  = $sb->get_dbh_for($node2);

   my $node2_slave = "master3";

   diag("Creating a slave for $node2...");
   {
      local $ENV{BINLOG_FORMAT} = 'ROW';
      $sb->start_sandbox("slave", $node2_slave, $node2);
   }
   my $node_slave_dbh = $sb->get_dbh_for($node2_slave);

   make_dbh_differ($node2_dbh);

   # And make its slave differ as well
   PerconaTest::wait_for_table($node_slave_dbh, "bug_1062563.ptc_pxc");
   $node_slave_dbh->do("INSERT INTO bug_1062563.ptc_pxc (i) VALUES ($_)") for 3, 4;

   my $dsns_table_sql = catfile(qw(t lib samples MasterSlave dsn_table.sql));
   $sb->load_file($node2, $dsns_table_sql, undef, no_wait => 1);
   my $sth = $node2_dbh->prepare("INSERT INTO dsn_t.dsns VALUES (null, null, ?)");
   for my $dsn ( map { $sb->dsn_for($_) } @nodes[0,2..$#nodes], $node2_slave ) {
      $sth->execute($dsn);
   }

   my $node2_dsn = $sb->dsn_for($node2);
   $output = output(
      sub { pt_table_checksum::main(
         $node2_dsn, qw(--lock-wait-timeout 3),
         qw(-d bug_1062563),
         '--recursion-method', "dsn=D=dsn_t,t=dsns"
      ) },
      stderr => 1,
   );

   is(
      PerconaTest::count_checksum_results($output, 'diffs'),
      1,
      "Bug 1062563: Detects diffs between PXC nodes"
   );

   my @cluster_nodes = $output =~ /(because it is a cluster node)/g;
   is(
      scalar(@cluster_nodes),
      4,
      "Skips all the cluster nodes in the dsns table"
   ) or diag($output);


   # Now try with just the slave

   $node2_dbh->do("DELETE FROM dsn_t.dsns");
   $sth->execute($sb->dsn_for($node2_slave));

   $output = output(
      sub { pt_table_checksum::main(
         $node2_dsn, qw(--lock-wait-timeout 3),
         qw(--chunk-size 1),
         qw(-d bug_1062563),
         '--recursion-method', "dsn=D=dsn_t,t=dsns"
      ) },
      stderr => 1,
   );

   is(
      PerconaTest::count_checksum_results($output, 'diffs'),
      1,
      "Bug 1062563: Detects diffs on slaves where the master is a PXC node"
   ) or diag($output);

   $sth->finish();
   diag("Stopping the PXC cluster and the slave...");
   $sb->stop_sandbox($node2_slave, @nodes);
   
   # Now checking that cluster -> cluster works
   
   diag("Creating two 3-node clusters...");
   my @cluster1   = $sb->start_cluster(cluster_size => 3, cluster_name => "pt_test_cluster_1");
   my @cluster2   = $sb->start_cluster(cluster_size => 3, cluster_name => "pt_test_cluster_2");
   diag("Cluster 1: ", Dumper( { map { $_ => $sb->port_for($_) } @cluster1 } ));
   diag("Cluster 2: ", Dumper( { map { $_ => $sb->port_for($_) } @cluster2 } ));
   
   $sb->set_as_slave($cluster2[0], $cluster1[0]);
   
   my $cluster1_dbh = $sb->get_dbh_for($cluster1[0]);
   my $cluster2_dbh = $sb->get_dbh_for($cluster2[0]);
   make_dbh_differ($cluster1_dbh);

   # And make its slave differ as well
   PerconaTest::wait_for_table($cluster2_dbh, "bug_1062563.ptc_pxc");
   $cluster2_dbh->do("INSERT INTO bug_1062563.ptc_pxc (i) VALUES ($_)") for 3, 4;
   
   $dsns_table_sql = catfile(qw(t lib samples MasterSlave dsn_table.sql));
   $sb->load_file($cluster1[0], $dsns_table_sql, undef, no_wait => 1);
   $sth = $cluster1_dbh->prepare("INSERT INTO dsn_t.dsns VALUES (null, null, ?)");
   for my $dsn ( map { $sb->dsn_for($_) } @cluster1[1..$#cluster1], $cluster2[0] ) {
      $sth->execute($dsn);
   }
   $sth->finish();
   
   my $cluster1_dsn = $sb->dsn_for($cluster1[0]);
   $output = output(
      sub { pt_table_checksum::main(
         $cluster1_dsn, qw(--lock-wait-timeout 3),
         qw(-d bug_1062563),
         '--recursion-method', "dsn=D=dsn_t,t=dsns"
      ) },
      stderr => 1,
   );

   is(
      PerconaTest::count_checksum_results($output, 'diffs'),
      1,
      "Bug 1062563: Detects diffs between PXC nodes when cluster -> cluster"
   );

   like(
      $output,
      qr/is a cluster node, but doesn't belong to the same cluster as/, #'
      "Shows a warning when cluster -> cluster"
   ) or diag($output);

   diag("Starting master1...");
   $sb->start_sandbox("master", "master1");
   diag("Setting it as master of a node in the first cluster");
   $sb->set_as_slave($cluster1[0], "master1");

   my $master1_dbh = $sb->get_dbh_for("master1");
   make_dbh_differ($master1_dbh, 10..50);
   
   my $master1_dsn = $sb->dsn_for("master1");
   $output = output(
      sub { pt_table_checksum::main(
         $master1_dsn, qw(--lock-wait-timeout 3),
         qw(-d bug_1062563),
      ) },
      stderr => 1,
   );

   is(
      PerconaTest::count_checksum_results($output, 'diffs'),
      1,
      "Bug 1062563: Detects diffs when master -> cluster"
   ) or diag($output);

   is(
      PerconaTest::count_checksum_results($output, 'rows'),
      41,
      "Bug 1062563: Correct number of rows for master -> cluster"
   ) or diag($output);
   
   like(
      $output,
      qr/is a cluster node, but .*? is not. This is not currently supported/,
      "Shows a warning when master -> cluster"
   ) or diag($output);
   
   diag("Stopping both clusters and master1...");
   $sb->stop_sandbox(@cluster1, @cluster2, "master1");

}

sub make_dbh_differ {
   my ($dbh, @vals) = @_;
   @vals = (@vals ? @vals : 1);
   # Make them differ...
   $dbh->do("DROP DATABASE IF EXISTS bug_1062563");
   $dbh->do("CREATE DATABASE bug_1062563");
   $dbh->do("CREATE TABLE bug_1062563.ptc_pxc (i int)");

   # Now make this node different from the rest
   $dbh->do("set sql_log_bin=0");
   $dbh->do("INSERT INTO bug_1062563.ptc_pxc (i) VALUES ($_)") for @vals;
   $dbh->do("set sql_log_bin=1");
}

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
