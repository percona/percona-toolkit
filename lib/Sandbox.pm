# This program is copyright 2008-2012 Percona Ireland Ltd.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
# ###########################################################################
# Sandbox package
# ###########################################################################
{
# Package: Sandbox
# Sandbox is an API for the test suite to access and control sandbox servers.
package Sandbox;

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::HiRes qw(sleep);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;
use constant PTDEBUG    => $ENV{PTDEBUG}    || 0;
use constant PTDEVDEBUG => $ENV{PTDEVDEBUG} || 0;

use IO::Socket::INET;

my $trunk = $ENV{PERCONA_TOOLKIT_BRANCH};

my %port_for = (
   master  => 12345,
   slave1  => 12346,
   slave2  => 12347,
   master1 => 12348, # master-master
   master2 => 12349, # master-master
   master3 => 2900,
   master4 => 2901,
   master5 => 2902,
   master6 => 2903,
   node1   => 12345, # pxc...
   node2   => 12346,
   node3   => 12347,
   node4   => 2900,
   node5   => 2901,
   node6   => 2902,
   node7   => 2903,
   cmaster => 12349, # master -> cluster
   cslave1 => 12348, # cluster -> slave
   host1   => 12345, # pt-upgrade
   host2   => 12348, # pt-upgrade
);

my %server_type = (
   master => 1,
   slave  => 1,
   node   => 1,
);

my $test_dbs = qr/^(?:mysql|information_schema|sakila|performance_schema|percona_test)$/;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(basedir DSNParser) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   if ( !-d $args{basedir} ) {
      die "$args{basedir} is not a directory";
   }

   return bless { %args }, $class;
}

sub use {
   my ( $self, $server, $cmd ) = @_;
   _check_server($server);
   return if !defined $cmd || !$cmd;
   my $use = $self->_use_for($server) . " $cmd";
   PTDEBUG && _d('"Executing', $use, 'on', $server);
   my $out = `$use 2>&1`;
   if ( $? >> 8 ) {
      die "Failed to execute $cmd on $server: $out";
   }
   return $out;
}

sub create_dbs {
   my ( $self, $dbh, $dbs, %args ) = @_;
   die 'I need a dbh' if !$dbh;
   return if ( !ref $dbs || scalar @$dbs == 0 );
   my %default_args = (
      repl => 1,
      drop => 1,
   );
   %args = ( %default_args, %args );

   $dbh->do('SET SQL_LOG_BIN=0') unless $args{repl};

   foreach my $db ( @$dbs ) {
      $dbh->do("DROP DATABASE IF EXISTS `$db`") if $args{drop};

      my $sql = "CREATE DATABASE `$db`";
      eval {
         $dbh->do($sql);
      };
      die $EVAL_ERROR if $EVAL_ERROR;
   }

   $dbh->do('SET SQL_LOG_BIN=1');

   return;
}
   
sub get_dbh_for {
   my ( $self, $server, $cxn_ops, $user ) = @_;
   _check_server($server);
   $cxn_ops ||= { AutoCommit => 1 };
   $user    ||= 'msandbox';
   PTDEBUG && _d('dbh for', $server, 'on port', $port_for{$server});
   my $dp = $self->{DSNParser};
   my $dsn = $dp->parse("h=127.0.0.1,u=$user,p=msandbox,P=" . $port_for{$server});
   my $dbh;
   # This is primarily for the benefit of CompareResults, but it's
   # also quite convenient when using an affected OS
   # TODO: this fails if the server isn't started yet.
   $cxn_ops->{L} = 1 if !exists $cxn_ops->{L}
                     && !$self->can_load_data('master');
   eval { $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), $cxn_ops) };
   if ( $EVAL_ERROR ) {
      die 'Failed to get dbh for ' . $server . ': ' . $EVAL_ERROR;
   }
   $dbh->{InactiveDestroy}  = 1; # Prevent destroying on fork.
   $dbh->{FetchHashKeyName} = 'NAME_lc' unless $cxn_ops && $cxn_ops->{no_lc};
   return $dbh;
}

sub load_file {
   my ( $self, $server, $file, $use_db, %args ) = @_;
   _check_server($server);
   $file = "$trunk/$file";
   if ( !-f $file ) {
      die "$file is not a file";
   }

   my $d = $use_db ? "-D $use_db" : '';

   my $use = $self->_use_for($server) . " $d < $file";
   PTDEBUG && _d('Loading', $file, 'on', $server, ':', $use);
   my $out = `$use 2>&1`;
   if ( $? >> 8 ) {
      die "Failed to execute $file on $server: $out";
   }
   $self->wait_for_slaves() unless $args{no_wait};
}

sub _use_for {
   my ( $self, $server ) = @_;
   return "$self->{basedir}/$port_for{$server}/use";
}

sub _check_server {
   my ( $server ) = @_;
   if ( !exists $port_for{$server} ) {
      die "Unknown server $server";
   }
   return;
}

sub wipe_clean {
   my ( $self, $dbh ) = @_;
   # If any other connections to the server are holding metadata locks, then
   # the DROP commands will just hang forever.
   my @cxns = @{$dbh->selectall_arrayref('SHOW FULL PROCESSLIST', {Slice => {}})};
   foreach my $cxn ( @cxns ) {
      if (( 
         (($cxn->{user}||'') eq 'msandbox' && ($cxn->{command}||'') eq 'Sleep')
      || (($cxn->{User}||'') eq 'msandbox' && ($cxn->{Command}||'') eq 'Sleep')
         ) && $cxn->{db} 
      ) {
         my $id  = $cxn->{id} ? $cxn->{id} : $cxn->{Id};
         my $sql = "KILL $id /* db: $cxn->{db} */";
         Test::More::diag($sql);
         eval { $dbh->do($sql); };
         Test::More::diag("Error executing $sql in Sandbox::wipe_clean(): "
            . $EVAL_ERROR) if $EVAL_ERROR;
      }
   }
   foreach my $db ( @{$dbh->selectcol_arrayref('SHOW DATABASES')} ) {
      next if $db =~ m/$test_dbs/;
      $dbh->do("DROP DATABASE IF EXISTS `$db`");
   }

   $self->wait_for_slaves();

   return;
}

# Returns a string if there is a problem with the master.
sub master_is_ok {
   my ($self, $master) = @_;
   my $master_dbh = $self->get_dbh_for($master);
   if ( !$master_dbh ) {
      return "Sandbox $master " . $port_for{$master} . " is down.";
   }
   $master_dbh->disconnect();
   return;
}

# Returns a string if there is a problem with the slave.
sub slave_is_ok {
   my ($self, $slave, $master, $ro) = @_;
   return if $self->is_cluster_node($slave);
   PTDEBUG && _d('Checking if slave', $slave, $port_for{$slave},
      'to', $master, $port_for{$master}, 'is ok');

   my $slave_dbh = $self->get_dbh_for($slave);
   if ( !$slave_dbh ) {
      return  "Sandbox $slave " . $port_for{$slave} . " is down.";
   }

   my $master_port = $port_for{$master};
   my $status = $slave_dbh->selectall_arrayref(
      "SHOW SLAVE STATUS", { Slice => {} });
   if ( !$status || !@$status ) {
      return "Sandbox $slave " . $port_for{$slave} . " is not a slave.";
   }

   if ( $status->[0]->{last_error} ) {
      warn Dumper($status);
      return "Sandbox $slave " . $port_for{$slave} . " is broken: "
         . $status->[0]->{last_error} . ".";
   }

   foreach my $thd ( qw(slave_io_running slave_sql_running) ) {
      if ( ($status->[0]->{$thd} || 'No') eq 'No' ) {
         warn Dumper($status);
         return "Sandbox $slave " . $port_for{$slave} . " $thd thread "
            . "is not running.";
      }
   }

   if ( $ro ) {
      my $row = $slave_dbh->selectrow_arrayref(
         "SHOW VARIABLES LIKE 'read_only'");
      if ( !$row || $row->[1] ne 'ON' ) {
         return "Sandbox $slave " . $port_for{$slave} . " is not read-only.";
      }
   }

   my $sleep_t = 0.25;
   my $total_t = 0;
   while ( defined $status->[0]->{seconds_behind_master}
           &&  $status->[0]->{seconds_behind_master} > 0 ) {
      PTDEBUG && _d('Slave lag:', $status->[0]->{seconds_behind_master});
      sleep $sleep_t;
      $total_t += $sleep_t;
      $status = $slave_dbh->selectall_arrayref(
         "SHOW SLAVE STATUS", { Slice => {} });
      if ( $total_t == 5 ) {
         Test::More::diag("Waiting for sandbox $slave " . $port_for{$slave}
            . " to catch up...");
      }
   }

   PTDEBUG && _d('Slave', $slave, $port_for{$slave}, 'is ok');
   $slave_dbh->disconnect();
   return;
}

# Returns a string if any leftoever servers were left running.
sub leftover_servers {
   my ($self) = @_;
   PTDEBUG && _d('Checking for leftover servers');
   foreach my $serverno ( 1..6 ) {
      my $server = "master$serverno";
      my $dbh = eval { $self->get_dbh_for($server) };
      if ( $dbh ) {
         $dbh->disconnect();
         return "Sandbox $server " . $port_for{$server} . " was left up.";
      }
   }
   return;
}

sub leftover_databases {
   my ($self, $host) = @_;
   PTDEBUG && _d('Checking for leftover databases');
   my $dbh = $self->get_dbh_for($host);
   my $dbs = $dbh->selectall_arrayref("SHOW DATABASES");
   $dbh->disconnect();
   my @leftover_dbs = map { $_->[0] } grep { $_->[0] !~ m/$test_dbs/ } @$dbs;
   if ( @leftover_dbs ) {
      return "Databases are left on $host: " . join(', ', @leftover_dbs);
   }
   return;
}

# This returns an empty string if all servers and data are OK. If it returns
# anything but empty string, there is a problem, and the string indicates what
# the problem is.
sub ok {
   my ($self) = @_;
   my @errors;
   # First, wait for all slaves to be caught up to their masters.
   $self->wait_for_slaves();
   push @errors, $self->master_is_ok('master');
   push @errors, $self->slave_is_ok('slave1', 'master');
   push @errors, $self->slave_is_ok('slave2', 'slave1', 1);
   push @errors, $self->leftover_servers();
   foreach my $host ( qw(master slave1 slave2) ) {
      push @errors, $self->leftover_databases($host);
      push @errors, $self->verify_test_data($host);
   }

   @errors = grep { warn "ERROR: ", $_, "\n" if $_; $_; } @errors;
   return !@errors;
}

# Dings a heartbeat on the master, and waits until the slave catches up fully.
sub wait_for_slaves {
   my ($self, %args) = @_;
   my $master_dbh = $self->get_dbh_for($args{master} || 'master');
   my $slave2_dbh = $self->get_dbh_for($args{slave}  || 'slave2');
   my ($ping) = $master_dbh->selectrow_array("SELECT MD5(RAND())");
   $master_dbh->do("UPDATE percona_test.sentinel SET ping='$ping' WHERE id=1 /* wait_for_slaves */");
   PerconaTest::wait_until(
      sub {
         my ($pong) = $slave2_dbh->selectrow_array(
            "SELECT ping FROM percona_test.sentinel WHERE id=1 /* wait_for_slaves */");
         return $ping eq ($pong || '');
      }, undef, 300
   );
}

# Verifies that master, slave1, and slave2 have a faithful copy of the mysql and
# sakila databases. The reference data is inserted into percona_test.checksums
# by util/checksum-test-dataset when sandbox/test-env starts the environment.
sub verify_test_data {
   my ($self, $host) = @_;

   # Get the known-good checksums from the master.
   my $master = $self->get_dbh_for('master');
   my $ref    = $self->{checksum_ref} || $master->selectall_hashref(
         'SELECT * FROM percona_test.checksums',
         'db_tbl');
   $self->{checksum_ref} = $ref unless $self->{checksum_ref};
   my @tables_in_mysql  = grep { !/^(?:innodb|slave)_/ }
                          grep { !/_log$/ }
                          @{$master->selectcol_arrayref('SHOW TABLES FROM mysql')};
   my @tables_in_sakila = qw(actor address category city country customer
                             film film_actor film_category film_text inventory
                             language payment rental staff store);
   $master->disconnect;

   # Get the current checksums on the host.
   my $dbh = $self->get_dbh_for($host);
   my $sql = "CHECKSUM TABLES "
           . join(", ", map { "mysql.$_" } @tables_in_mysql)
           . ", "
           . join(", ", map { "sakila.$_" } @tables_in_sakila);

   # remove leading "," if any
   $sql =~ s/CHECKSUM TABLES\s+,/CHECKSUM TABLES /;

   my @checksums = @{$dbh->selectall_arrayref($sql, {Slice => {} })};

   # Diff the two sets of checksums: host to master (ref).
   my @diffs;
   foreach my $c ( @checksums ) {
      next unless $c->{checksum};
      if ( $c->{checksum} ne $ref->{$c->{table}}->{checksum} ) {
         push @diffs, $c->{table};
      }
   }
   $dbh->disconnect;

   if ( @diffs ) {
      return "Tables are different on $host: " . join(', ', @diffs);
   }
   return;
}

sub dsn_for {
   my ($self, $host) = @_;
   _check_server($host);
   return "h=127.1,P=$port_for{$host},u=msandbox,p=msandbox";
}

sub cnf_for {
   my ($self, $host) = @_;
   _check_server($host);
   return "/tmp/" . $port_for{$host} . "/my.sandbox.cnf";
}

sub genlog {
   my ($self, $host) = @_;
   _check_server($host);
   return "/tmp/$port_for{$host}/data/genlog";
}

sub clear_genlogs {
   my ($self, @hosts) = @_;
   @hosts = qw(master slave1 slave2) unless scalar @hosts;
   foreach my $host ( @hosts ) {
      PTDEVDEBUG && _d('Clearing general log on', $host);
      Test::More::diag(`echo > /tmp/$port_for{$host}/data/genlog`);
   }
   return;
}

sub is_cluster_mode {
   my ($self) = @_;
   return 0 unless $self->is_cluster_node('node1');
   return 0 unless $self->is_cluster_node('node2');
   return 0 unless $self->is_cluster_node('node3');
   return 1;
}

sub is_cluster_node {
   my ($self, $server) = @_;

   my $sql = "SHOW VARIABLES LIKE 'wsrep_on'";
   PTDEBUG && _d($sql);
   my $row = $self->use($server, qq{-ss -e "$sql"});
   PTDEBUG && _d($row);
   $row = [split " ", $row];

   return $row && $row->[1] && ($row->[1] eq 'ON' || $row->[1] eq '1');
}

sub can_load_data {
    my ($self, $server) = @_;
    my $output = $self->use($server, q{-e "SELECT * FROM percona_test.load_data"});
    return ($output || '') =~ /1/;
}

sub set_as_slave {
   my ($self, $server, $master_server, @extras) = @_;
   PTDEBUG && _d("Setting $server as slave of $master_server");
   my $master_port = $port_for{$master_server};
   my $sql = join ", ", qq{change master to master_host='127.0.0.1'},
                        qq{master_user='msandbox'},
                        qq{master_password='msandbox'},
                        qq{master_port=$master_port},
                        @extras;
   for my $sql_to_run ($sql, "start slave") {
      my $out = $self->use($server, qq{-e "$sql_to_run"});
      PTDEBUG && _d($out);
   }
}

sub start_sandbox {
   my ($self, %args) = @_;
   my @required_args = qw(type server);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my ($type, $server) = @args{@required_args};
   my $env = $args{env} || '';

   die "Invalid server type: $type" unless $server_type{$type};
   _check_server($server);
   my $port = $port_for{$server};

   if ( $type eq 'master') {
      my $out = `$env $trunk/sandbox/start-sandbox $type $port`;
      die $out if $CHILD_ERROR;
   }
   elsif ( $type eq 'slave' ) {
      die "I need a slave arg" unless $args{master};
      _check_server($args{master});
      my $master_port = $port_for{$args{master}};

      my $out = `$env $trunk/sandbox/start-sandbox $type $port $master_port`;
      die $out if $CHILD_ERROR;
   }
   elsif ( $type eq 'node' ) {
      my $first_node = $args{first_node} ? $port_for{$args{first_node}} : '';
      my $out = `$env $trunk/sandbox/start-sandbox cluster $port $first_node`;
      die $out if $CHILD_ERROR;
   }

   my $dbh = $self->get_dbh_for($server, $args{cxn_opts});
   my $dsn = $self->dsn_for($server);

   return $dbh, $dsn;
}

sub stop_sandbox {
   my ($self, @sandboxes) = @_;
   my @ports = @port_for{@sandboxes};
   my $out = `$trunk/sandbox/stop-sandbox @ports`;
   die $out if $CHILD_ERROR;
   return $out;
}

sub start_cluster {
   my ($self, %args) = @_;
   my @required_args = qw(nodes);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my ($nodes) = @args{@required_args};

   foreach my $node ( @$nodes ) {
      _check_server($node);
   }

   Test::More::diag("Starting cluster with @$nodes");
   my %connect;

   my $first_node = shift @$nodes;
   my ($dbh, $dsn) = $self->start_sandbox(
      type   => "node",
      server => $first_node,
      env    => $args{env},
   );
   $connect{$first_node} = { dbh => $dbh, dsn => $dsn };

   foreach my $node ( @$nodes ) {
      my ($dbh, $dsn) = $self->start_sandbox(
         server     => $node,
         type       => "node",
         first_node => $first_node,
         env        => $args{env},
      );
      $connect{$node} = { dbh => $dbh, dsn => $dsn };
   }

   return \%connect;
}

sub port_for {
   my ($self, $server) = @_;
   return $port_for{$server};
}

sub config_file_for {
   my ($self, $server) = @_;
   my $port = $self->port_for($server);
   return "/tmp/$port/my.sandbox.cnf"
}

sub do_as_root {
   my ($self, $server, @queries) = @_;
   my $dbh = $self->get_dbh_for($server, undef, 'root');
   my $ok = 1;
   eval {
      foreach my $query ( @queries ) {
         $dbh->do($query);
      }
   };
   if ( $EVAL_ERROR ) {
      $ok = 0;
      warn $EVAL_ERROR;
   }
   $dbh->disconnect;
   return $ok;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Sandbox package
# ###########################################################################
