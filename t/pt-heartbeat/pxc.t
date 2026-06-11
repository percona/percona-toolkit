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

use File::Temp qw(tempfile);

use PerconaTest;
use Sandbox;

require "$trunk/bin/pt-heartbeat";
# Do this after requiring pt-hb, since it uses Mo
require VersionParser;

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

my $db_flavor = VersionParser->new($node1)->flavor();
if ( $db_flavor !~ /XtraDB Cluster/ ) {
   plan skip_all => "PXC tests";
}

my $node1_dsn  = $sb->dsn_for('node1');
my $node2_dsn  = $sb->dsn_for('node2');
my $node3_dsn  = $sb->dsn_for('node3');
my $node1_port = $sb->port_for('node1');
my $node2_port = $sb->port_for('node2');
my $node3_port = $sb->port_for('node3');

my $output;
my $exit;
my $base_pidfile = (tempfile("/tmp/pt-heartbeat-test.XXXXXXXX", OPEN => 0, UNLINK => 0))[1];
my $sample = "t/pt-heartbeat/samples/";

my $sentinel = '/tmp/pt-heartbeat-sentinel';

# Remove any leftover instances
diag(`$trunk/bin/pt-heartbeat --stop >/dev/null`);
sleep 1;

diag(`rm -rf $sentinel >/dev/null 2>&1`);
$sb->create_dbs($node1, ['test']);

my @exec_pids;
my @pidfiles;

sub start_update_instance {
   my ($port) = @_;
   my $pidfile = "$base_pidfile.$port.pid";
   push @pidfiles, $pidfile;

   my $pid = fork();
   die "Cannot fork: $OS_ERROR" unless defined $pid;
   if ( $pid == 0 ) {
      my $cmd = "$trunk/bin/pt-heartbeat";
      exec { $cmd } $cmd, qw(-h 127.0.0.1 -u msandbox -p msandbox -P), $port,
                          qw(--database test --table heartbeat --create-table),
                          qw(--update --interval 0.5 --pid), $pidfile;
      exit 1;
   }
   push @exec_pids, $pid;

   PerconaTest::wait_for_files($pidfile);
   ok(
      -f $pidfile,
      "--update on $port started"
   );
}

sub stop_all_instances {
   my @pids = @exec_pids, map { chomp; $_ } map { slurp_file($_) } @pidfiles;
   diag(`$trunk/bin/pt-heartbeat --stop >/dev/null`);

   waitpid($_, 0) for @pids;
   PerconaTest::wait_until(sub{ !-e $_ }) for @pidfiles;

   unlink $sentinel;
}

foreach my $port ( map { $sb->port_for($_) } qw(node1 node2 node3) ) {
   start_update_instance($port);
}

# #############################################################################
# Basic cluster tests
# #############################################################################

my $rows = $node1->selectall_hashref("select * from test.heartbeat", 'server_id');

is(
   scalar keys %$rows,
   3,
   "Sanity check: All nodes are in the heartbeat table"
);

# These values may be 0 or '' depending on whether or not a previous test
# turned 12345 into a replica or not.  For this purpose 0 == undef == ''.
my $only_replica_data = {
   map {
      $_ => {
         relay_source_log_file => $rows->{$_}->{"relay_${source_name}_log_file"} || undef,
         exec_source_log_pos   => $rows->{$_}->{"exec_${source_name}_log_pos"}   || undef,
      } } keys %$rows
};

my $same_data = { relay_${source_name}_log_file => undef, exec_${source_name}_log_pos => undef };
is_deeply(
   $only_replica_data,
   {
      12345 => $same_data,
      12346 => $same_data,
      12347 => $same_data,
   },
   "Sanity check: No replica data (relay log or source pos) is stored"
) or diag(Dumper($rows));

$output = output(sub{
      pt_heartbeat::main($node1_dsn, qw(-D test --check)),
   },
   stderr => 1,
);

like(
   $output,
   qr/\QThe --${source_name}-server-id option must be specified because the heartbeat table `test`.`heartbeat`/,
   "pt-heartbeat --check + PXC doesn't autodetect a source if there isn't any"
);

$output = output(sub{
      pt_heartbeat::main($node1_dsn, qw(-D test --check),
                         '--${source_name}-server-id', $node3_port),
   },
   stderr => 1,
);

$output =~ s/\d\.\d{2}/0.00/g;
is(
   $output,
   "0.00\n",
   "pt-heartbeat --check + PXC works with --source-server-id"
);

# Test --monitor

$output = output(sub {
   pt_heartbeat::main($node1_dsn,
      qw(-D test --monitor --run-time 1s),
      '--${source_name}-server-id', $node3_port)
   },
   stderr => 1,
);

$output =~ s/\d\.\d{2}/0.00/g;
is(
   $output,
   "0.00s [  0.00s,  0.00s,  0.00s ]\n",
   "--monitor works"
);

# Try to generate some lag between cluster nodes. Rather brittle at the moment.

# Lifted from alter active table
my $pt_osc_sample      = "t/pt-online-schema-change/samples";

my $query_table_stop   = "/tmp/query_table.$PID.stop";
my $query_table_pid    = "/tmp/query_table.$PID.pid";
my $query_table_output = "/tmp/query_table.$PID.output";

$sb->create_dbs($node1, ['pt_osc']);
$sb->load_file('source', "$pt_osc_sample/basic_no_fks_innodb.sql");

$node1->do("USE pt_osc");
$node1->do("TRUNCATE TABLE t");
$node1->do("LOAD DATA INFILE '$trunk/$pt_osc_sample/basic_no_fks.data' INTO TABLE t");
$node1->do("ANALYZE TABLE t");
$sb->wait_for_replicas();

diag(`rm -rf $query_table_stop`);
diag(`echo > $query_table_output`);

my $cmd = "$trunk/$pt_osc_sample/query_table.pl";
system("$cmd 127.0.0.1 $node1_port pt_osc t id $query_table_stop $query_table_pid >$query_table_output 2>&1 &");
wait_until(sub{-e $query_table_pid});

# Reload sakila
system "$trunk/sandbox/load-sakila-db $node1_port &";

$output = output(sub {
   pt_heartbeat::main($node3_dsn,
      qw(-D test --monitor --run-time 5s),
      '--${source_name}-server-id', $node1_port)
   },
   stderr => 1,
);

like(
   $output,
   qr/^(?:0\.(?:\d[1-9]|[1-9]\d)|\d*[1-9]\d*\.\d{2})s\s+\[/m,
   "pt-heartbeat can detect replication lag between nodes"
);

diag(`touch $query_table_stop`);
chomp(my $p = slurp_file($query_table_pid));
wait_until(sub{!kill 0, $p});

$node1->do(q{DROP DATABASE pt_osc});

$sb->wait_for_replicas();

# #############################################################################
# cluster, node1 -> replica, run on node1
# #############################################################################

my ($replica_dbh, $replica_dsn) = $sb->start_sandbox(
   server => 'creplica1',
   type   => 'replica',
   source => 'node1',
   env    => q/FORK="pxc" BINLOG_FORMAT="ROW"/,
);

$sb->create_dbs($replica_dbh, ['test']);
$sb->wait_for_replicas(source => 'node1', replica => 'creplica1');
start_update_instance($sb->port_for('creplica1'));
PerconaTest::wait_for_table($replica_dbh, "test.heartbeat", "1=1");

$output = output(sub{
      pt_heartbeat::main($replica_dsn, qw(-D test --check)),
   },
   stderr => 1,
);

like(
   $output,
   qr/\d\.\d{2}\n/,
   "pt-heartbeat --check works on a replica of a cluster node"
);

$output = output(sub {
   pt_heartbeat::main($replica_dsn,
      qw(-D test --monitor --run-time 2s))
   },
   stderr => 1,
);

like(
   $output,
   qr/^\d.\d{2}s\s+\[/,
   "pt-heartbeat --monitor + replica of a node1, without --source-server-id"
);

$output = output(sub {
   pt_heartbeat::main($replica_dsn,
      qw(-D test --monitor --run-time 2s),
      '--${source_name}-server-id', $node3_port)
   },
   stderr => 1,
);

like(
   $output,
   qr/^\d.\d{2}s\s+\[/,
   "pt-heartbeat --monitor + replica of node1, --source-server-id pointing to node3"
);

# #############################################################################
# source -> node1 in cluster
# #############################################################################

# CAREFUL! See the comments in t/pt-table-checksum/pxc.t about csource.
# Nearly everything applies here.

my ($source_dbh, $source_dsn) = $sb->start_sandbox(
   server => 'csource',
   type   => 'source',
   env    => q/FORK="pxc" BINLOG_FORMAT="ROW"/,
);

my $csource_port = $sb->port_for('csource');

$sb->create_dbs($source_dbh, ['test']);
$source_dbh->do("INSERT INTO percona_test.sentinel (id, ping) VALUES (1, '')");
$source_dbh->do("FLUSH LOGS");
$source_dbh->do("RESET ${source_reset}");

$sb->set_as_replica('node1', 'csource');
$sb->wait_for_replicas(source => 'csource', replica => 'node1');

start_update_instance($sb->port_for('csource'));
PerconaTest::wait_for_table($node1, "test.heartbeat", "server_id=$csource_port");

# Auto-detecting the source id only works when ran on node1, the direct
# replica of the source, because other nodes aren't replicas, but this could
# be made to work; see the node autodiscovery branch.
$output = output(
   sub {
      pt_heartbeat::main($node1_dsn,
         qw(-D test --check --print-${source_name}-server-id)
   )},
   stderr => 1,
);

like(
   $output,
   qr/^\d.\d{2} $csource_port$/,
   "Auto-detect source ID from node1"
);

# Wait until node2 & node3 get csource in their heartbeat tables
$sb->wait_for_replicas(source => 'node1', replica => 'node2');
$sb->wait_for_replicas(source => 'node1', replica => 'node3');

foreach my $test (
   [ $node2_port, $node2_dsn, $node2, 'node2' ],
   [ $node3_port, $node3_dsn, $node3, 'node3' ],
) {
   my ($port, $dsn, $dbh, $name) = @$test;
   
   $output = output(
      sub {
         pt_heartbeat::main($dsn,
            qw(-D test --check --print-${source_name}-server-id)
      )},
      stderr => 1,
   );

   like(
      $output,
      qr/server's ${source_name} could not be automatically determined/,
      "Limitation: cannot auto-detect source id from $name"
   );

   $output = output(
      sub {
         pt_heartbeat::main($dsn,
            qw(-D test --check --${source_name}-server-id), $csource_port
      )},
      stderr => 1,
   );

   $output =~ s/\d\.\d{2}/0.00/g;

   is(
      $output,
      "0.00\n",
      "$name --check --source-server-id $csource_port"
   );
}

# ############################################################################
# Stop the --update instances.
# ############################################################################

stop_all_instances();

# ############################################################################
# Disconnect & stop the two servers we started
# ############################################################################

# We have to do this after the --stop, otherwise the --update processes will
# spew a bunch of warnings and clog 

$replica_dbh->disconnect;
$source_dbh->disconnect;
$sb->stop_sandbox('creplica1', 'csource');
$node1->do("STOP ${replica_name}");
$node1->do("RESET ${replica_name}");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($node1);
diag(`/tmp/12345/stop`);
diag(`/tmp/12345/start`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
