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

use MasterSlave;
use DSNParser;
use VersionParser;
use OptionParser;
use Quoter;
use Cxn;
use Sandbox;
use PerconaTest;

use Data::Dumper;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $master_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');
my $master_dsn = {
   h => '127.1',
   P => '12345',
   u => 'msandbox',
   p => 'msandbox',
};

my $q = new Quoter;
my $o = new OptionParser(description => 'MasterSlave');
$o->get_specs("$trunk/bin/pt-table-checksum");

my $ms = new MasterSlave(
   OptionParser => $o,
   DSNParser    => $dp,
   Quoter       => $q,
);

# ############################################################################
# get_replicas() wrapper around recurse_to_replicas()
# ############################################################################

SKIP: {
   skip "Cannot connect to sandbox master", 2 unless $master_dbh;

PXC_SKIP: {
      skip 'Not for PXC' if ( $sb->is_cluster_mode );

      local @ARGV = ();
      $o->get_opts();

      my $slaves = $ms->get_replicas(
         dbh      => $master_dbh,
         dsn      => $master_dsn,
         make_cxn => sub {
            my $cxn = new Cxn(
               @_,
               DSNParser    => $dp,
               OptionParser => $o,
            );
            $cxn->connect();
            return $cxn;
         },
      );

      is_deeply(
         $slaves->[0]->dsn(),
         {  A => undef,
            D => undef,
            F => undef,
            P => '12346',
            S => undef,
            h => '127.0.0.1',
            p => 'msandbox',
            t => undef,
            s => undef,
            u => 'msandbox',
            server_id => 12346,
            source_id => 12345,
            source    => 'hosts',
         },
         'get_replicas() from recurse_to_replicas() with a default --recursion-method'
      ) or diag(Dumper($slaves->[0]->dsn()));

      my ($id) = $slaves->[0]->dbh()->selectrow_array('SELECT @@SERVER_ID');
      is(
         $id,
         '12346',
         'dbh created from get_replicas()'
      );

      # This doesn't actually work because the master and slave are both
      # localhost/127.1 so it will connect agian to the master, detect this,
      # and ignore it.  This tests nonetheless that "processlist" isn't
      # misspelled, which would cause the sub to die.
      # https://bugs.launchpad.net/percona-toolkit/+bug/921802
      local @ARGV = ('--recursion-method', 'processlist');
      $o->get_opts();

      $slaves = $ms->get_replicas(
         dbh      => $master_dbh,
         dsn      => $master_dsn,
         make_cxn => sub {
            my $cxn = new Cxn(
               @_,
               DSNParser    => $dp,
               OptionParser => $o,
            );
            $cxn->connect();
            return $cxn;
         },
      );

      is_deeply(
         $slaves,
         [],
         "get_replicas() by processlist"
      );

      # ##########################################################################
      # --recursion-method=none
      # https://bugs.launchpad.net/percona-toolkit/+bug/987694
      # ##########################################################################

      # Create percona.checksums to make the privs happy.
      diag(`/tmp/12345/use -e "create database if not exists percona"`);
      diag(`/tmp/12345/use -e "create table if not exists percona.checksums (id int)"`);

      # Create a read-only checksum user that can't SHOW SLAVES HOSTS or much else.
      diag(`/tmp/12345/use -u root < $trunk/t/lib/samples/ro-checksum-user.sql`);

      my $ro_dbh = DBI->connect(
         "DBI:mysql:;host=127.0.0.1;port=12345;mysql_ssl=1", 'ro_checksum_user', 'msandbox',
              { PrintError => 0, RaiseError => 1 });
      my $ro_dsn = {
         h => '127.1',
         P => '12345',
         u => 'ro_checksum_user',
         p => 'ro_checksum_user',
      };

      @ARGV = ('--recursion-method', 'hosts');
      $o->get_opts();
      throws_ok(
         sub {
            $slaves = $ms->get_replicas(
               dbh      => $ro_dbh,
               dsn      => $ro_dsn,
               make_cxn => sub {
                  my $cxn = new Cxn(
                     @_,
                     DSNParser    => $dp,
                     OptionParser => $o,
                  );
                  $cxn->connect();
                  return $cxn;
               },
            );
         },
         qr/Access denied/,
         "Can't SHOW SLAVE HOSTS without privs (bug 987694)"
      );

      @ARGV = ('--recursion-method', 'none');
      $o->get_opts();
      $slaves = $ms->get_replicas(
         dbh      => $ro_dbh,
         dsn      => $ro_dsn,
         make_cxn => sub {
            my $cxn = new Cxn(
               @_,
               DSNParser    => $dp,
               OptionParser => $o,
            );
            $cxn->connect();
            return $cxn;
         },
      );
      is_deeply(
         $slaves,
         [],
         "No privs needed for --recursion-method=none (bug 987694)"
      );

      @ARGV = ('--recursion-method', 'none', '--recurse', '2');
      $o->get_opts();
      my $recursed = 0;
      $ms->recurse_to_replicas(
         {  dbh      => $ro_dbh,
            dsn      => $ro_dsn,
            callback => sub { $recursed++ },
         });
      is(
         $recursed,
         0,
         "recurse_to_replicas() doesn't recurse if method=none"
      );

      $ro_dbh->disconnect();
      diag(`/tmp/12345/use -u root -e "drop user 'ro_checksum_user'\@'%'"`);

      # ##########################################################################
      # Test that get_replicas doesn't leak connections when called multiple times
      # This verifies that Cxn objects without preserve_dbh properly clean up
      # ##########################################################################

      @ARGV = ('--recursion-method', 'hosts');
      $o->get_opts();

      # Track connection thread IDs we create so we can verify cleanup
      my @disposable_thread_ids;
      my $replicas = $ms->get_replicas(
            dbh      => $master_dbh,
            dsn      => $master_dsn,
            make_cxn => sub {
               my $cxn = new Cxn(
                  @_,
                  DSNParser    => $dp,
                  OptionParser => $o,
                  preserve_dbh => 1, # there will be a fork in this test, we need this persistent
               );
               $cxn->connect();
               return $cxn;
            },
         );

      # Call get_replicas multiple times in a loop
      # Each iteration should create Cxn objects and then clean them up
      # As soon as object loses reference, perl should DESTROY Cxn and related connections
      for my $iteration (1..5) {
         my $tmp_replicas = $ms->get_replicas(
            dbh      => $master_dbh,
            dsn      => $master_dsn,
            make_cxn => sub {
               my $cxn = new Cxn(
                  @_,
                  DSNParser    => $dp,
                  OptionParser => $o,
                  # NOT setting preserve_dbh, so connections should be cleaned up
               );
               $cxn->connect();
               return $cxn;
            },
         );

         # Verify we got replicas
         ok(
            scalar(@$tmp_replicas) > 0,
            "get_replicas iteration $iteration returned replicas"
         );

         # Collect thread IDs from the replica connections
         foreach my $cxn (@$tmp_replicas) {
            if ($cxn && $cxn->dbh) {
               my $thread_id = $cxn->dbh->{mysql_thread_id};
               push @disposable_thread_ids, $thread_id;
            }
         }
      }

      my $placeholders = join(',', map { '?' } @disposable_thread_ids);
      for my $cxn (@$replicas) {
        my ($leaked_connections,) = $cxn->dbh->selectrow_array(
            "SELECT COUNT(*)
            FROM information_schema.processlist
            WHERE id IN ($placeholders)",
            { Slice => {} },
            @disposable_thread_ids
        );

        ok($leaked_connections eq 0, 'No remaining connection from get_replicas');
      }

      # Test the opposite now: with preserve_dbh=1, read-replicas should not close connection when going out of scope
      # like in a fork scenario
      my @preserved_thread_ids;
      {
          my $replicas_preserved = $ms->get_replicas(
              dbh      => $master_dbh,
              dsn      => $master_dsn,
              make_cxn => sub {
                  my $cxn = new Cxn(
                      @_,
                      DSNParser    => $dp,
                      OptionParser => $o,
                      preserve_dbh => 1,
                  );
                  $cxn->connect();
                  return $cxn;
              },
          );

          my $pid = fork();
          if ( defined($pid) && $pid == 0 ) {
              # We are in the child process
              # this would trigger destruction of read replicas in child process
              # as preserve_dbh was set to 1, the connection will remain
              exit;
          }
          for my $cxn (@$replicas_preserved) {
              if ($cxn && $cxn->dbh) {
                  push @preserved_thread_ids, $cxn->dbh->{mysql_thread_id};
              }
          }
      }

      $placeholders = join(',', map { '?' } @preserved_thread_ids);
      for my $cxn (@$replicas) {
        $cxn->{preserve_dbh} = 0; # enable deletion of our probe replica connection
        my $leaked_connections = $cxn->dbh->selectall_arrayref(
            "SELECT ID
            FROM information_schema.processlist
            WHERE id IN ($placeholders)",
            { Slice => {} },
            @preserved_thread_ids
        );

        my $count_leaked_conn = scalar @$leaked_connections;
        ok($count_leaked_conn > 0, "Had $count_leaked_conn remaining connection from get_replicas");

        # Test done, let's now kill connections to prevent a leak in the test database
        for my $thread (@$leaked_connections) {
            eval {
                $cxn->dbh->do("KILL $thread->{id}");
            };
            warn "Failed to kill thread $thread->{id}: $@" if $@;
        }
      }
   }
}
# #############################################################################
# First we need to setup a special replication sandbox environment apart from
# the usual persistent sandbox servers on ports 12345 and 12346.
# The tests in this script require a master with 3 slaves in a setup like:ggn
#    127.0.0.1:master
#    +- 127.0.0.1:slave0
#    |  +- 127.0.0.1:slave1
#    +- 127.0.0.1:slave2
# The servers will have the ports (which won't conflict with the persistent
# sandbox servers) as seen in the %port_for hash below.
# #############################################################################
my %port_for = (
   source => 2900,
   replica0 => 2901,
   replica1 => 2902,
   replica2 => 2903,
);
foreach my $port ( values %port_for ) {
   if ( -d "/tmp/$port" ) {
      diag(`$trunk/sandbox/stop-sandbox $port >/dev/null 2>&1`);
   }
}
diag(`$trunk/sandbox/start-sandbox source 2900`);
diag(`$trunk/sandbox/start-sandbox replica 2903 2900`);
diag(`$trunk/sandbox/start-sandbox replica 2901 2900`);
diag(`$trunk/sandbox/start-sandbox replica 2902 2901`);

# We need to sleep, so source server updates list of replicas on fast machines.
sleep(1);

# I discovered something weird while updating this test. Above, you see that
# slave2 is started first, then the others. Before, slave2 was started last,
# but this caused the tests to fail because SHOW SLAVE HOSTS on the master
# returned:
# +-----------+-----------+------+-------------------+-----------+
# | Server_id | Host      | Port | Rpl_recovery_rank | Master_id |
# +-----------+-----------+------+-------------------+-----------+
# |      2903 | 127.0.0.1 | 2903 |                 0 |      2900 | 
# |      2901 | 127.0.0.1 | 2901 |                 0 |      2900 | 
# +-----------+-----------+------+-------------------+-----------+
# This caused recurse_to_replicas() to report 2903, 2901, 2902.
# Since the tests are senstive to the order of @slaves, they failed
# because $slaves->[1] was no longer slave1 but slave0. Starting slave2
# last fixes/works around this.

# #############################################################################
# Now the test.
# #############################################################################
my $dbh;
my @slaves;
my @sldsns;

my $dsn = $dp->parse("h=127.0.0.1,P=$port_for{source},u=msandbox,p=msandbox,s=>1");
$dbh    = $dp->get_dbh($dp->get_cxn_params($dsn), { AutoCommit => 1 });

my $callback = sub {
   my ( $dsn, $dbh, $level, $parent ) = @_;
   return unless $level;
   ok($dsn, "Connected to one slave "
      . ($dp->as_string($dsn) || '<none>')
      . " from $dsn->{source}");
   push @slaves, $dbh;
   push @sldsns, $dsn;
};

my $skip_callback = sub {
   my ( $dsn, $dbh, $level ) = @_;
   return unless $level;
   ok($dsn, "Skipped one slave "
      . ($dp->as_string($dsn) || '<none>')
      . " from $dsn->{source}");
};

@ARGV = ('--recurse', '2');
$o->get_opts();

$ms->recurse_to_replicas(
   {  dbh           => $dbh,
      dsn           => $dsn,
      callback      => $callback,
      skip_callback => $skip_callback,
   });

is(
   scalar(@slaves),
   3,
   "recurse to slaves finds all three slaves"
) or diag(Dumper(\@slaves));

is_deeply(
   $ms->get_source_dsn( $slaves[0], undef, $dp ),
   {  h => '127.0.0.1',
      u => undef,
      P => $port_for{source},
      S => undef,
      F => undef,
      p => undef,
      D => undef,
      A => undef,
      t => undef,
      s => undef,
   },
   'Got master DSN',
);

# The picture:
# 127.0.0.1:master
# +- 127.0.0.1:slave0
# |  +- 127.0.0.1:slave1
# +- 127.0.0.1:slave2
is($ms->get_replica_status($slaves[0])->{"${source_name}_port"}, $port_for{source}, 'slave 1 port');
is($ms->get_replica_status($slaves[1])->{"${source_name}_port"}, $port_for{replica0}, 'slave 2 port');
is($ms->get_replica_status($slaves[2])->{"${source_name}_port"}, $port_for{source}, 'slave 3 port');

ok($ms->is_source_of($slaves[0], $slaves[1]), 'slave 1 is slave of slave 0');
eval {
   $ms->is_source_of($slaves[0], $slaves[2]);
};
like($EVAL_ERROR, qr/but the source's port/, 'slave 2 is not slave of slave 0') or diag($EVAL_ERROR);
eval {
   $ms->is_source_of($slaves[2], $slaves[1]);
};
like($EVAL_ERROR, qr/has no connected replicas/, 'slave 1 is not slave of slave 2');

map { $ms->stop_replica($_) } @slaves;
map { $ms->start_replica($_) } @slaves;

# Give the slaves so time to restart
sleep(5);

my $res;
$res = $ms->wait_for_source(
   source_status => $ms->get_source_status($dbh),
   replica_dbh     => $slaves[0],
   timeout       => 10,
);

ok($res->{result} >= 0, 'Wait was successful');

$ms->stop_replica($slaves[0]);
$dbh->do('drop database if exists test');
$dbh->do('create database test');
$dbh->do('create table test.t(a int)');
$dbh->do('insert into test.t(a) values(1)');
$dbh->do('update test.t set a=sleep(5)');
diag(`(/tmp/$port_for{replica0}/use -e 'start ${replica_name}')&`);
eval {
   $res = $ms->wait_for_source(
      source_status => $ms->get_source_status($dbh),
      replica_dbh     => $slaves[0],
      timeout       => 1,
   );
};
ok($res->{result}, 'Waited for some events');

# Clear any START SLAVE UNTIL conditions.
map { $ms->stop_replica($_) } @slaves;
map { $ms->start_replica($_) } @slaves;
sleep 1;

$ms->stop_replica($slaves[0]);
$dbh->do('drop database if exists test'); # Any stmt will do
eval {
   $res = $ms->catchup_to_source($slaves[0], $dbh, 10);
};
diag $EVAL_ERROR if $EVAL_ERROR;
ok(!$EVAL_ERROR, 'No eval error catching up');
my $master_stat = $ms->get_source_status($dbh);
my $slave_stat = $ms->get_replica_status($slaves[0]);
is_deeply(
   $ms->repl_posn($master_stat),
   $ms->repl_posn($slave_stat),
   'Caught up');

# #############################################################################
# Test is_replication_thread()
# #############################################################################
my $query = {
   Id      => '302',
   User    => 'msandbox',
   Host    => 'localhost',
   db      => 'NULL',
   Command => 'Query',
   Time    => '0',
   State   => 'NULL',
   Info    => 'show processlist',
};

ok(
   !$ms->is_replication_thread($query),
   "Non-rpl thd is not repl thd"
);

ok(
   !$ms->is_replication_thread($query, type=>'binlog_dump', check_known_ids=>0),
   "Non-rpl thd is not binlog dump thd"
);

ok(
   !$ms->is_replication_thread($query, type=>'replica_io', check_known_ids=>0),
   "Non-rpl thd is not slave io thd"
);

ok(
   !$ms->is_replication_thread($query, type=>'replica_sql', check_known_ids=>0),
   "Non-rpl thd is not slave sql thd"
);

$query = {
   Id      => '7',
   User    => 'msandbox',
   Host    => 'localhost:53246',
   db      => 'NULL',
   Command => 'Binlog Dump',
   Time    => '1174',
   State   => 'Sending binlog event to slave',
   Info    => 'NULL',
},

ok(
   $ms->is_replication_thread($query, check_known_ids=>0),
   'Binlog Dump is a repl thd'
);

ok(
   !$ms->is_replication_thread($query, type=>'replica_io', check_known_ids=>0),
   'Binlog Dump is not a slave io thd'
);

ok(
   !$ms->is_replication_thread($query, type=>'replica_sql', check_known_ids=>0),
   'Binlog Dump is not a slave sql thd'
);

$query = {
   Id      => '7',
   User    => 'system user',
   Host    => '',
   db      => 'NULL',
   Command => 'Connect',
   Time    => '1174',
   State   => 'Waiting for master to send event',
   Info    => 'NULL',
},

ok(
   $ms->is_replication_thread($query, check_known_ids=>0),
   'Slave io thd is a repl thd'
);

ok(
   $ms->is_replication_thread($query, type=>'replica_io', check_known_ids=>0),
   'Slave io thd is a slave io thd'
);

ok(
   !$ms->is_replication_thread($query, type=>'replica_sql', check_known_ids=>0),
   'Slave io thd is not a slave sql thd',
);

$query = {
   Id      => '7',
   User    => 'system user',
   Host    => '',
   db      => 'NULL',
   Command => 'Connect',
   Time    => '1174',
   State   => 'Has read all relay log; waiting for the slave I/O thread to update it',
   Info    => 'NULL',
},

ok(
   $ms->is_replication_thread($query, check_known_ids=>0),
   'Slave sql thd is a repl thd'
);

ok(
   !$ms->is_replication_thread($query, type=>'replica_io', check_known_ids=>0),
   'Slave sql thd is not a slave io thd'
);

ok(
   $ms->is_replication_thread($query, type=>'replica_sql', check_known_ids=>0),
   'Slave sql thd is a slave sql thd',
);

# Issue 1121: mk-kill Occasionally Kills Slave Replication Threads
$query = {
   Command  => 'Connect',
   Host     => '',
   Id       => '466963',
   Info     => 'delete from my_table where l_id=217263 and s_id=1769',
   State    => 'init',
   Time     => '0',
   User     => 'system user',
   db       => 'mydatabase',
};
ok(
   $ms->is_replication_thread($query),
   'Slave thread in init state matches all (issue 1121)',
);
ok(
   $ms->is_replication_thread($query, type=>'replica_io'),
   'Slave thread in init state matches replica_io (issue 1121)',
);
ok(
   $ms->is_replication_thread($query, type=>'replica_sql'),
   'Slave thread in init state matches replica_sql (issue 1121)',
);

# Issue 1143: mk-kill Can Kill Slave's Replication Thread
# Same thread id as previous, so it's still the repl thread,
# but it's executing a trigger so it looks like a normal thread.
$query = {
   Command  => 'Connect',
   Host     => 'localhost',
   Id       => '466963',
   Info     => 'INSERT IGNORE INTO tbl VALUES (NEW.id, NEW.name,  0)',
   State    => 'update',
   Time     => '15',
   User     => 'root',
   db       => 'mydatabase',
};
ok(
   $ms->is_replication_thread($query),
   'Slave thread executing trigger matches all (issue 1143)',
);
ok(
   $ms->is_replication_thread($query, type=>'replica_io'),
   'Slave thread executing trigger matches replica_io (issue 1143)',
);
ok(
   $ms->is_replication_thread($query, type=>'replica_sql'),
   'Slave thread executing trigger matches replica_sql (issue 1143)',
);

throws_ok(
   sub { $ms->is_replication_thread($query, type=>'foo') },
   qr/Invalid type: foo/,
   "Invalid repl thread type"
);

# ############################################################################
# Bug 819421: MasterSlave::is_replication_thread() doesn't match all
# Issue 1339: MasterSlave::is_replication_thread() doesn't match all
# ############################################################################
$query = {
   Id      => '7',
   User    => 'msandbox',
   Host    => 'localhost:53246',
   db      => 'NULL',
   Command => 'Binlog Dump',
   Time    => '1174',
   State   => 'Sending binlog event to slave',
   Info    => 'NULL',
},

ok(
   $ms->is_replication_thread($query, type=>'all'),
   'Explicit all matches binlog dump'
);

$query = {
   Id      => '7',
   User    => 'system user',
   Host    => '',
   db      => 'NULL',
   Command => 'Connect',
   Time    => '1174',
   State   => 'Waiting for master to send event',
   Info    => 'NULL',
};

ok(
   $ms->is_replication_thread($query, type=>'all'),
   'Explicit all matches slave io thread'
);

$query = {
   Id      => '7',
   User    => 'system user',
   Host    => '',
   db      => 'NULL',
   Command => 'Connect',
   Time    => '1174',
   State   => 'Has read all relay log; waiting for the slave I/O thread to update it',
   Info    => 'NULL',
};

ok(
   $ms->is_replication_thread($query, type=>'all'),
   'Explicit all matches slave sql thread'
);

# #############################################################################
# get_replication_filters()
# #############################################################################
SKIP: {
   skip "Cannot connect to sandbox master", 3 unless $master_dbh;
   skip "Cannot connect to sandbox slave", 3 unless $replica_dbh;

PXC_SKIP: {
      skip 'Not for PXC' if ( $sb->is_cluster_mode );

   is_deeply(
      $ms->get_replication_filters(dbh=>$replica_dbh),
      {
      },
      "No replication filters"
   );

   $master_dbh->disconnect();
   $replica_dbh->disconnect();

   diag(`/tmp/12346/stop >/dev/null 2>&1`);
   diag(`/tmp/12345/stop >/dev/null 2>&1`);
   diag(`cp /tmp/12346/my.sandbox.cnf /tmp/12346/orig.cnf`);
   diag(`cp /tmp/12345/my.sandbox.cnf /tmp/12345/orig.cnf`);
   diag(`echo "replicate-ignore-db=foo" >> /tmp/12346/my.sandbox.cnf`);
   diag(`echo "binlog-ignore-db=bar" >> /tmp/12345/my.sandbox.cnf`);
   diag(`/tmp/12345/start >/dev/null 2>&1`);
   diag(`/tmp/12346/start >/dev/null 2>&1`);
   
   $master_dbh = $sb->get_dbh_for('source');
   $replica_dbh  = $sb->get_dbh_for('replica1');

   is_deeply(
      $ms->get_replication_filters(dbh=>$master_dbh),
      {
         binlog_ignore_db => 'bar',
      },
      "Master replication filter"
   );

   is_deeply(
      $ms->get_replication_filters(dbh=>$replica_dbh),
      {
         replicate_ignore_db => 'foo',
      },
      "Slave replication filter"
   );
   
   diag(`/tmp/12346/stop >/dev/null`);
   diag(`/tmp/12345/stop >/dev/null`);
   diag(`mv /tmp/12346/orig.cnf /tmp/12346/my.sandbox.cnf`);
   diag(`mv /tmp/12345/orig.cnf /tmp/12345/my.sandbox.cnf`);
   diag(`/tmp/12345/start >/dev/null`);
   diag(`/tmp/12346/start >/dev/null`);
   diag(`/tmp/12347/use -e "STOP ${replica_name}; START ${replica_name};" >/dev/null`);

   $master_dbh = $sb->get_dbh_for('source');
   $replica_dbh  = $sb->get_dbh_for('replica1');
};

is(
   $ms->get_replica_lag($dbh),
   undef,
   "get_replica_lag() for master"
);

ok(
   defined $ms->get_replica_lag($slaves[1]),
   "get_replica_lag() for slave"
);

# ############################################################################
# get_replicas() and DSN table
# ############################################################################
$sb->load_file('source', "t/lib/samples/MasterSlave/dsn_table.sql");

@ARGV = ('--recursion-method', 'dsn=F=/tmp/12345/my.sandbox.cnf,D=dsn_t,t=dsns');
$o->get_opts();

my $slaves = $ms->get_replicas(
   OptionParser => $o,
   DSNParser    => $dp,
   Quoter       => $q,
   make_cxn     => sub {
      my $cxn = new Cxn(
         @_,
         DSNParser    => $dp,
         OptionParser => $o,
      );
      $cxn->connect();
      return $cxn;
   },
   dsn => 'F=/tmp/12345/my.sandbox.cnf',
);

is_deeply(
   $slaves->[0]->{dsn},
   {  A => undef,
      D => undef,
      F => undef,
      P => '12346',
      S => undef,
      h => '127.1',
      p => 'msandbox',
      t => undef,
      u => 'msandbox',
      s => undef,
   },
   'get_replicas() from DSN table'
);

my ($id) = $slaves->[0]->dbh()->selectrow_array('SELECT @@SERVER_ID');
is(
   $id,
   '12346',
   'dbh created from DSN table works'
);
}

# ############################################################################
# --replica-user/--replica-password with DSN recursion method
# ############################################################################
$sb->load_file('source', "t/lib/samples/MasterSlave/dsn_table_undef.sql");
$replica_dbh->do('drop user if exists replica_user');
$replica_dbh->do("create user replica_user identified by 'replica_password'");
$sb->do_as_root('replica1', 'grant replication slave on *.* to replica_user');
@ARGV = (
   '--recursion-method', 'dsn=F=/tmp/12345/my.sandbox.cnf,D=dsn_t,t=dsns',
   '--replica-user',     'replica_user',
   '--replica-password', 'replica_password',
);
$o->get_opts();

my $slaves = $ms->get_replicas(
   OptionParser => $o,
   DSNParser    => $dp,
   Quoter       => $q,
   make_cxn     => sub {
      my $cxn = new Cxn(
         @_,
         DSNParser    => $dp,
         OptionParser => $o,
      );
      $cxn->connect();
      return $cxn;
   },
   dsn => 'F=/tmp/12345/my.sandbox.cnf',
);

is(
   $slaves->[0]->{dsn}->{u},
   'replica_user',
   '--replica-user is applied to DSN recursion entries without user'
);

is(
   $slaves->[0]->{dsn}->{p},
   'replica_password',
   '--replica-password is applied to DSN recursion entries without password'
);

$replica_dbh->do('drop user if exists replica_user');

$sb->load_file('source', "t/lib/samples/MasterSlave/dsn_table.sql");
@ARGV = ('--recursion-method', 'dsn=F=/tmp/12345/my.sandbox.cnf,D=dsn_t,t=dsns');
$o->get_opts();

$slaves = $ms->get_replicas(
   OptionParser => $o,
   DSNParser    => $dp,
   Quoter       => $q,
   make_cxn     => sub {
      my $cxn = new Cxn(
         @_,
         DSNParser    => $dp,
         OptionParser => $o,
      );
      $cxn->connect();
      return $cxn;
   },
   dsn => 'F=/tmp/12345/my.sandbox.cnf',
);

is(
   $slaves->[0]->{dsn}->{u},
   'msandbox',
   '--replica-user does not override DSN user'
);

is(
   $slaves->[0]->{dsn}->{p},
   'msandbox',
   '--replica-password does not override DSN password'
);

# ############################################################################
# Invalid recursion methods are caught
# ############################################################################
eval {
   MasterSlave::check_recursion_method([qw(stuff)])
};
like(
   $EVAL_ERROR,
   qr/Invalid recursion method: stuff/,
   "--recursion-method stuff causes error"
);

eval {
   MasterSlave::check_recursion_method([qw(processlist stuff)])
};
like(
   $EVAL_ERROR,
   qr/Only hosts and processlist may be combined/,
   "--recursion-method processlist,stuff causes error",
);

eval {
   MasterSlave::check_recursion_method([qw(none hosts)])
};
like(
   $EVAL_ERROR,
   qr/Only hosts and processlist may be combined/,
   "--recursion-method none,hosts"
);

eval {
   MasterSlave::check_recursion_method([qw(cluster none)])
};
like(
   $EVAL_ERROR,
   qr/Only hosts and processlist may be combined/,
   "--recursion-method cluster,none"
);

eval {
   MasterSlave::check_recursion_method([qw(none none)])
};
like(
   $EVAL_ERROR,
   qr/Only hosts and processlist may be combined/,
   "--recursion-method none,none"
);

SKIP: {

   skip "Only test on mysql 5.7",6 if ( $sandbox_version lt '5.7' );

   my ($master1_dbh, $master1_dsn) = $sb->start_sandbox(
      server => 'chan_source1',
      type   => 'source',
   );
   my ($master2_dbh, $master2_dsn) = $sb->start_sandbox(
      server => 'chan_source2',
      type   => 'source',
   );
   my ($slave1_dbh, $slave1_dsn) = $sb->start_sandbox(
      server => 'chan_replica1',
      type   => 'source',
   );
   my $slave1_port = $sb->port_for('chan_replica1');
   
   if ( $sandbox_version lt '8.1' ) {
      $sb->load_file('chan_source1', "sandbox/gtid_on-legacy.sql", undef, no_wait => 1);
      $sb->load_file('chan_source2', "sandbox/gtid_on-legacy.sql", undef, no_wait => 1);
      $sb->load_file('chan_replica1', "sandbox/replica_channels-legacy.sql", undef, no_wait => 1);
   } else {
      $sb->load_file('chan_source1', "sandbox/gtid_on.sql", undef, no_wait => 1);
      $sb->load_file('chan_source2', "sandbox/gtid_on.sql", undef, no_wait => 1);
      $sb->load_file('chan_replica1', "sandbox/replica_channels.sql", undef, no_wait => 1);
   }
                                                             
   my $chan_slaves;
   eval {
       $chan_slaves = $ms->get_replicas(
          dbh      => $master1_dbh,
          dsn      => $master1_dsn,
          make_cxn => sub {
             my $cxn = new Cxn(
                @_,
                DSNParser    => $dp,
                OptionParser => $o,
             );
             $cxn->connect();
             return $cxn;
          },
       );
   };

   #local $SIG{__WARN__} = sub {
   #   $message = shift;
   #};
   my $css;
   eval {
       $css = $ms->get_replica_status($slave1_dbh);
   };
   #local $SIG{__WARN__} = undef;
   is (
       $css,
       undef,
       'Cannot determine slave in a multi source config without --channel param'
   );

   like (
       $EVAL_ERROR,
       qr/This server returned more than one row for SHOW (REPLICA|SLAVE) STATUS/,
       'Got warning message if we cannot determine replica in a multi source config without --channel param',
   );

   my $wfm;
   eval {
       $wfm = $ms->wait_for_source(
          source_status => $ms->get_source_status($dbh),
          replica_dbh     => $slave1_dbh,
          timeout       => 1,
       );
   };
   warn ">>>>>> @_" if @_;

   like(
       $wfm->{error},
       qr/"channel" was not specified on the command line/,
       'Wait for master returned error',
   );

   # After stopping one of the replication channels, show slave status returns only one slave
   # but it has a channel name and we didn't specified a channels name in the command line.
   # It should return undef
   $slave1_dbh->do("STOP ${replica_name} for channel 'sourcechan2'");

   eval {
       $css = $ms->get_replica_status($slave1_dbh);
   };
   is (
       $css,
       undef,
       'Cannot determine slave in a multi source config without --channel param (only one server)'
   );

   $slave1_dbh->do("START ${replica_name} for channel 'sourcechan2'");

   # Now try specifying a channel name 
   $ms->{channel} = 'sourcechan1';
   $css = $ms->get_replica_status($slave1_dbh);
   is (
       $css->{channel_name},
       'sourcechan1',
       'Returned the correct slave',
   );

   $wfm = $ms->wait_for_source(
      source_status => $ms->get_source_status($dbh),
      replica_dbh     => $slave1_dbh,
      timeout       => 1,
   );
   is(
       $wfm->{error},
       undef,
       'Wait for master returned no error',
   );

   $sb->stop_sandbox(qw(chan_source1 chan_source2 chan_replica1));
}

my $connected_slaves = [
  {
    command => 'Binlog Dump',
    db => undef,
    host => '2001:db8:1::242:ac11:3:53902',
    id => 7,
    info => undef,
    rows_examined => 0,
    rows_sent => 0,
    state => 'Master has sent all binlog to slave; waiting for more updates',
    time => 80,
    user => 'root'
  },
];

my @g = $ms->_process_replicas_list ($dp, $dsn, $connected_slaves);
is (
    scalar @g,
    1,
    "1 slave (IPv6) detected",
);
is (
    $g[0]->{h},
    "[2001:db8:1::242:ac11:3]",
    "Brackets were added to IPv6 detected slave host",
);
# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
diag(`$trunk/sandbox/stop-sandbox 2903 2902 2901 2900`);
diag(`/tmp/12346/use -e "set global read_only=1"`);
diag(`/tmp/12347/use -e "set global read_only=1"`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
