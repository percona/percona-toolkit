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

my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');
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
# get_slaves() wrapper around recurse_to_slaves()
# ############################################################################

SKIP: {
   skip "Cannot connect to sandbox master", 2 unless $master_dbh;
   local @ARGV = ();
   $o->get_opts();
   
   my $slaves = $ms->get_slaves(
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
         u => 'msandbox',
         server_id => 12346,
         master_id => 12345,
         source    => 'hosts',
      },
      'get_slaves() from recurse_to_slaves() with a default --recursion-method'
   );

   my ($id) = $slaves->[0]->dbh()->selectrow_array('SELECT @@SERVER_ID');
   is(
      $id,
      '12346',
      'dbh created from get_slaves()'
   );

   # This doesn't actually work because the master and slave are both
   # localhost/127.1 so it will connect agian to the master, detect this,
   # and ignore it.  This tests nonetheless that "processlist" isn't
   # misspelled, which would cause the sub to die.
   # https://bugs.launchpad.net/percona-toolkit/+bug/921802
   local @ARGV = ('--recursion-method', 'processlist');
   $o->get_opts();

   $slaves = $ms->get_slaves(
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
      "get_slaves() by processlist"
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
      "DBI:mysql:;host=127.0.0.1;port=12345", 'ro_checksum_user', 'msandbox',
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
         $slaves = $ms->get_slaves(
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
   $slaves = $ms->get_slaves(
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
   $ms->recurse_to_slaves(
      {  dbh      => $ro_dbh,
         dsn      => $ro_dsn,
         callback => sub { $recursed++ },
      });
   is(
      $recursed,
      0,
      "recurse_to_slaves() doesn't recurse if method=none"
   );

   $ro_dbh->disconnect();
   diag(`/tmp/12345/use -u root -e "drop user 'ro_checksum_user'\@'%'"`); 
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
   master => 2900,
   slave0 => 2901,
   slave1 => 2902,
   slave2 => 2903,
);
foreach my $port ( values %port_for ) {
   if ( -d "/tmp/$port" ) {
      diag(`$trunk/sandbox/stop-sandbox $port >/dev/null 2>&1`);
   }
}
diag(`$trunk/sandbox/start-sandbox master 2900`);
diag(`$trunk/sandbox/start-sandbox slave 2903 2900`);
diag(`$trunk/sandbox/start-sandbox slave 2901 2900`);
diag(`$trunk/sandbox/start-sandbox slave 2902 2901`);

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
# This caused recurse_to_slaves() to report 2903, 2901, 2902.
# Since the tests are senstive to the order of @slaves, they failed
# because $slaves->[1] was no longer slave1 but slave0. Starting slave2
# last fixes/works around this.

# #############################################################################
# Now the test.
# #############################################################################
my $dbh;
my @slaves;
my @sldsns;

my $dsn = $dp->parse("h=127.0.0.1,P=$port_for{master},u=msandbox,p=msandbox");
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

$ms->recurse_to_slaves(
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
   $ms->get_master_dsn( $slaves[0], undef, $dp ),
   {  h => '127.0.0.1',
      u => undef,
      P => $port_for{master},
      S => undef,
      F => undef,
      p => undef,
      D => undef,
      A => undef,
      t => undef,
   },
   'Got master DSN',
);

# The picture:
# 127.0.0.1:master
# +- 127.0.0.1:slave0
# |  +- 127.0.0.1:slave1
# +- 127.0.0.1:slave2
is($ms->get_slave_status($slaves[0])->{master_port}, $port_for{master}, 'slave 1 port');
is($ms->get_slave_status($slaves[1])->{master_port}, $port_for{slave0}, 'slave 2 port');
is($ms->get_slave_status($slaves[2])->{master_port}, $port_for{master}, 'slave 3 port');

ok($ms->is_master_of($slaves[0], $slaves[1]), 'slave 1 is slave of slave 0');
eval {
   $ms->is_master_of($slaves[0], $slaves[2]);
};
like($EVAL_ERROR, qr/but the master's port/, 'slave 2 is not slave of slave 0');
eval {
   $ms->is_master_of($slaves[2], $slaves[1]);
};
like($EVAL_ERROR, qr/has no connected slaves/, 'slave 1 is not slave of slave 2');

map { $ms->stop_slave($_) } @slaves;
map { $ms->start_slave($_) } @slaves;

my $res;
$res = $ms->wait_for_master(
   master_status => $ms->get_master_status($dbh),
   slave_dbh     => $slaves[0],
   timeout       => 1,
);
ok($res->{result} >= 0, 'Wait was successful');

$ms->stop_slave($slaves[0]);
$dbh->do('drop database if exists test');
$dbh->do('create database test');
$dbh->do('create table test.t(a int)');
$dbh->do('insert into test.t(a) values(1)');
$dbh->do('update test.t set a=sleep(5)');
diag(`(/tmp/$port_for{slave0}/use -e 'start slave')&`);
eval {
   $res = $ms->wait_for_master(
      master_status => $ms->get_master_status($dbh),
      slave_dbh     => $slaves[0],
      timeout       => 1,
   );
};
ok($res->{result}, 'Waited for some events');

# Clear any START SLAVE UNTIL conditions.
map { $ms->stop_slave($_) } @slaves;
map { $ms->start_slave($_) } @slaves;
sleep 1;

$ms->stop_slave($slaves[0]);
$dbh->do('drop database if exists test'); # Any stmt will do
eval {
   $res = $ms->catchup_to_master($slaves[0], $dbh, 10);
};
diag $EVAL_ERROR if $EVAL_ERROR;
ok(!$EVAL_ERROR, 'No eval error catching up');
my $master_stat = $ms->get_master_status($dbh);
my $slave_stat = $ms->get_slave_status($slaves[0]);
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
   !$ms->is_replication_thread($query, type=>'slave_io', check_known_ids=>0),
   "Non-rpl thd is not slave io thd"
);

ok(
   !$ms->is_replication_thread($query, type=>'slave_sql', check_known_ids=>0),
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
   !$ms->is_replication_thread($query, type=>'slave_io', check_known_ids=>0),
   'Binlog Dump is not a slave io thd'
);

ok(
   !$ms->is_replication_thread($query, type=>'slave_sql', check_known_ids=>0),
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
   $ms->is_replication_thread($query, type=>'slave_io', check_known_ids=>0),
   'Slave io thd is a slave io thd'
);

ok(
   !$ms->is_replication_thread($query, type=>'slave_sql', check_known_ids=>0),
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
   !$ms->is_replication_thread($query, type=>'slave_io', check_known_ids=>0),
   'Slave sql thd is not a slave io thd'
);

ok(
   $ms->is_replication_thread($query, type=>'slave_sql', check_known_ids=>0),
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
   $ms->is_replication_thread($query, type=>'slave_io'),
   'Slave thread in init state matches slave_io (issue 1121)',
);
ok(
   $ms->is_replication_thread($query, type=>'slave_sql'),
   'Slave thread in init state matches slave_sql (issue 1121)',
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
   $ms->is_replication_thread($query, type=>'slave_io'),
   'Slave thread executing trigger matches slave_io (issue 1143)',
);
ok(
   $ms->is_replication_thread($query, type=>'slave_sql'),
   'Slave thread executing trigger matches slave_sql (issue 1143)',
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
   skip "Cannot connect to sandbox slave", 3 unless $slave_dbh;

   is_deeply(
      $ms->get_replication_filters(dbh=>$slave_dbh),
      {
      },
      "No replication filters"
   );

   $master_dbh->disconnect();
   $slave_dbh->disconnect();

   diag(`/tmp/12346/stop >/dev/null 2>&1`);
   diag(`/tmp/12345/stop >/dev/null 2>&1`);
   diag(`cp /tmp/12346/my.sandbox.cnf /tmp/12346/orig.cnf`);
   diag(`cp /tmp/12345/my.sandbox.cnf /tmp/12345/orig.cnf`);
   diag(`echo "replicate-ignore-db=foo" >> /tmp/12346/my.sandbox.cnf`);
   diag(`echo "binlog-ignore-db=bar" >> /tmp/12345/my.sandbox.cnf`);
   diag(`/tmp/12345/start >/dev/null 2>&1`);
   diag(`/tmp/12346/start >/dev/null 2>&1`);
   
   $master_dbh = $sb->get_dbh_for('master');
   $slave_dbh  = $sb->get_dbh_for('slave1');

   is_deeply(
      $ms->get_replication_filters(dbh=>$master_dbh),
      {
         binlog_ignore_db => 'bar',
      },
      "Master replication filter"
   );

   is_deeply(
      $ms->get_replication_filters(dbh=>$slave_dbh),
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
   diag(`/tmp/12347/use -e "STOP SLAVE; START SLAVE;" >/dev/null`);

   $master_dbh = $sb->get_dbh_for('master');
   $slave_dbh  = $sb->get_dbh_for('slave1');
};

is(
   $ms->get_slave_lag($dbh),
   undef,
   "get_slave_lag() for master"
);

ok(
   defined $ms->get_slave_lag($slaves[1]),
   "get_slave_lag() for slave"
);

# ############################################################################
# get_slaves() and DSN table
# ############################################################################
$sb->load_file('master', "t/lib/samples/MasterSlave/dsn_table.sql");

@ARGV = ('--recursion-method', 'dsn=F=/tmp/12345/my.sandbox.cnf,D=dsn_t,t=dsns');
$o->get_opts();

my $slaves = $ms->get_slaves(
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
   },
   'get_slaves() from DSN table'
);

my ($id) = $slaves->[0]->dbh()->selectrow_array('SELECT @@SERVER_ID');
is(
   $id,
   '12346',
   'dbh created from DSN table works'
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
   qr/Invalid recursion method: stuff/,
   "--recursion-method processlist,stuff causes error",
);

eval {
   MasterSlave::check_recursion_method([qw(none hosts)])
};
like(
   $EVAL_ERROR,
   qr/none cannot be combined with other methods/,
   "--recursion-method none,hosts"
);

eval {
   MasterSlave::check_recursion_method([qw(cluster none)])
};
like(
   $EVAL_ERROR,
   qr/none cannot be combined with other methods/,
   "--recursion-method cluster,none"
);

eval {
   MasterSlave::check_recursion_method([qw(none none)])
};
like(
   $EVAL_ERROR,
   qr/Invalid combination of recursion methods: none, none/,
   "--recursion-method none,none"
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
