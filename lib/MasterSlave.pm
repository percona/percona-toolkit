# This program is copyright 2007-2011 Baron Schwartz, 2011-2026 Percona LLC and/or its affiliates.
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
# You should have received a copy of the GNU General Public License, version 2
# along with this program; if not, see <https://www.gnu.org/licenses/>.
# ###########################################################################
# MasterSlave package
# ###########################################################################
{
# Package: MasterSlave
# MasterSlave handles common tasks related to source-replica setups.
package MasterSlave;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Sub: check_recursion_method
#   Check that the arrayref of recursion methods passed in is valid
sub check_recursion_method {
   my ($methods) = @_;
   if ( @$methods != 1 ) {
      if ( grep({ !m/processlist|hosts/i } @$methods)
            && $methods->[0] !~ /^dsn=/i )
      {
         die  "Invalid combination of recursion methods: "
            . join(", ", map { defined($_) ? $_ : 'undef' } @$methods) . ". "
            . "Only hosts and processlist may be combined.\n"
      }
   }
   else {
      my ($method) = @$methods;
      die "Invalid recursion method: " . ( $method || 'undef' )
         unless $method && $method =~ m/^(?:processlist$|hosts$|none$|cluster$|dsn=)/i;
   }
}

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(OptionParser DSNParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      replication_thread => {},
   };
   return bless $self, $class;
}

sub get_replicas {
   my ($self, %args) = @_;
   my @required_args = qw(make_cxn);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($make_cxn) = @args{@required_args};

   my $replicas  = [];
   my $dp      = $self->{DSNParser};
   my $methods = $self->_resolve_recursion_methods($args{dsn});

   return $replicas unless @$methods;

   if ( grep { m/processlist|hosts/i } @$methods ) {
      my @required_args = qw(dbh dsn);
      foreach my $arg ( @required_args ) {
         die "I need a $arg argument" unless $args{$arg};
      }
      my ($dbh, $dsn) = @args{@required_args};
      my $o = $self->{OptionParser};

      $self->recurse_to_replicas(
         {  dbh              => $dbh,
            dsn              => $dsn,
            replica_user     => ( $o->got('replica-user') or $o->got('slave-user') ) ? $o->get('replica-user') : '',
            replica_password => ( $o->got('replica-password') or $o->got('slave-password') ) ? $o->get('replica-password') : '',
            replicas         => $args{replicas},
            callback  => sub {
               my ( $dsn, $dbh, $level, $parent ) = @_;
               return unless $level;
               PTDEBUG && _d('Found replica:', $dp->as_string($dsn));
               my $replica_dsn = $dsn;
               if ( $o->got('replica-user') or $o->got('slave-user') ) {
                  $replica_dsn->{u} = $o->get('replica-user');
                  PTDEBUG && _d("Using replica user ".$o->get('replica-user')." on ".$replica_dsn->{h}.":".$replica_dsn->{P});
               }
               if ( $o->got('replica-password') or $o->got('slave-password') ) {
                  $replica_dsn->{p} = $o->get('replica-password');
                  PTDEBUG && _d("Replica password set");
               }
               push @$replicas, $make_cxn->(dsn => $replica_dsn, dbh => $dbh, parent => $parent);
               return;
            },
            wait_no_die => $args{'wait_no_die'},
         }
      );
   } elsif ( $methods->[0] =~ m/^dsn=/i ) {
      my @required_args = qw(dsn);
      foreach my $arg ( @required_args ) {
         die "I need a $arg argument" unless $args{$arg};
      }
      my ($dsn) = @args{@required_args};
      (my $dsn_table_dsn = join ",", @$methods) =~ s/^dsn=//i;
      $replicas = $self->get_cxn_from_dsn_table(
         %args,
         dsn_table_dsn => $dsn_table_dsn,
         wait_no_die => $args{'wait_no_die'},
         # We will set current source server as a parent
         # until https://perconadev.atlassian.net/browse/PT-2496 is implemented
         parent => $dsn,
      );
   }
   elsif ( $methods->[0] =~ m/none/i ) {
      PTDEBUG && _d('Not getting to replicas');
   }
   else {
      die "Unexpected recursion methods: @$methods";
   }

   return $replicas;
}

sub _resolve_recursion_methods {
   my ($self, $dsn) = @_;
   my $o = $self->{OptionParser};
   if ( $o->got('recursion-method') ) {
      return $o->get('recursion-method');
   }
   elsif ( $dsn && ($dsn->{P} || 3306) != 3306 ) {
      # Special case: hosts is best when port is non-standard.
      PTDEBUG && _d('Port number is non-standard; using only hosts method');
      return [qw(hosts)];
   }
   else {
      # Use the option's default.
      return $o->get('recursion-method');
   }
}

# Sub: recurse_to_replicas
#   Descend to replicas by examining SHOW REPLICAS.
#   The callback gets the replica's DSN, dbh, parent, and the recursion level
#   as args.  The recursion is tail recursion.
#
# Parameters:
#   $args  - Hashref of arguments
#   $level - Recursion level
#
# Required Arguments:
#   dsn           - The DSN to connect to; if no dbh arg, connect using this.
#   recurse       - How many levels to recurse. 0 = none, undef = infinite.
#   callback      - Code to execute after finding a new replica.
#   dsn_parser    - <DSNParser> object
#
# Optional Arguments:
#   dbh           - dbh
#   skip_callback - Execute with replicas that will be skipped.
#   method        - Whether to prefer HOSTS over PROCESSLIST
#   parent        - The DSN from which this call descended.
sub recurse_to_replicas {
   my ( $self, $args, $level ) = @_;
   $level ||= 0;
   my $dp = $self->{DSNParser};
   my $recurse = $args->{recurse} || $self->{OptionParser}->get('recurse');
   my $dsn = $args->{dsn};
   my $replica_user = $args->{replica_user} || '';
   my $replica_password = $args->{replica_password} || '';

   my $methods = $self->_resolve_recursion_methods($dsn);
   PTDEBUG && _d('Recursion methods:', @$methods);
   if ( lc($methods->[0]) eq 'none' ) {
      PTDEBUG && _d('Not recursing to replicas');
      return;
   }

   my $replica_dsn = $dsn;
   if ($replica_user) {
      $replica_dsn->{u} = $replica_user;
      PTDEBUG && _d("Using replica user $replica_user on "
         . $replica_dsn->{h} . ":" . ( $replica_dsn->{P} ? $replica_dsn->{P} : ""));
   }
   if ($replica_password) {
      $replica_dsn->{p} = $replica_password;
      PTDEBUG && _d("Replica password set");
   }

   my $dbh = $args->{dbh};

   my $get_dbh = sub {
         eval {
            $dbh = $dp->get_dbh(
               $dp->get_cxn_params($replica_dsn), { AutoCommit => 1 }
            );
            PTDEBUG && _d('Connected to', $dp->as_string($replica_dsn));
         };
         if ( $EVAL_ERROR ) {
            print STDERR "Cannot connect to ", $dp->as_string($replica_dsn), ": ", $EVAL_ERROR, "\n"
               or die "Cannot print: $OS_ERROR";
            return;
         }
   };

   DBH: {
      if ( !defined $dbh ) {
         foreach my $known_replica ( @{$args->{replicas}} ) {
            if ($known_replica->{dsn}->{h} eq $replica_dsn->{h} and
                $known_replica->{dsn}->{P} eq $replica_dsn->{P} ) {
               $dbh = $known_replica->{dbh};
               last DBH;
            }
         }
         $get_dbh->();
      }
   }

   my $sql  = 'SELECT @@SERVER_ID';
   PTDEBUG && _d($sql);
   my $id = undef;
   do {
      eval {
         ($id) = $dbh->selectrow_array($sql);
      };
	   if ( $EVAL_ERROR ) {
		   if ( $args->{wait_no_die} ) {
			   print STDERR "Error getting server id: ", $EVAL_ERROR,
               "\nRetrying query for server ", $replica_dsn->{h}, ":", $replica_dsn->{P}, "\n";
            sleep 1;
            $dbh->disconnect();
            $get_dbh->();
         } else {
            die $EVAL_ERROR;
         }
      }
   } until (defined $id);
   PTDEBUG && _d('Working on server ID', $id);
   my $source_thinks_i_am = $dsn->{server_id};
   if ( !defined $id
       || ( defined $source_thinks_i_am && $source_thinks_i_am != $id )
       || $args->{server_ids_seen}->{$id}++
   ) {
      PTDEBUG && _d('Server ID seen, or not what source said');
      if ( $args->{skip_callback} ) {
         $args->{skip_callback}->($dsn, $dbh, $level, $args->{parent});
      }
      return;
   }

   $args->{callback}->($dsn, $dbh, $level, $args->{parent});

   if ( !defined $recurse || $level < $recurse ) {

      my @replicas =
         grep { !$_->{source_id} || $_->{source_id} == $id } # Only my replicas.
         $self->find_replica_hosts($dp, $dbh, $dsn, $methods);

      foreach my $replica ( @replicas ) {
         PTDEBUG && _d('Recursing from',
            $dp->as_string($dsn), 'to', $dp->as_string($replica));
         $self->recurse_to_replicas(
            { %$args, dsn => $replica, dbh => undef, parent => $dsn, replica_user => $replica_user, $replica_password => $replica_password }, $level + 1 );
      }
   }
}

# Finds replica hosts by trying different methods.  The default preferred method
# is trying SHOW PROCESSLIST (processlist) and guessing which ones are replicas,
# and if that doesn't reveal anything, then try SHOW REPLICA STATUS (hosts).
# One exception is if the port is non-standard (3306), indicating that the port
# from SHOW REPLICAS may be important.  Then only the hosts methods is used.
#
# Returns a list of DSN hashes.  Optional extra keys in the DSN hash are
# source_id and server_id.  Also, the 'source' key is either 'processlist' or
# 'hosts'.
#
# If a method is given, it becomes the preferred (first tried) method.
# Searching stops as soon as a method finds replicas.
sub find_replica_hosts {
   my ( $self, $dsn_parser, $dbh, $dsn, $methods ) = @_;

   PTDEBUG && _d('Looking for replicas on', $dsn_parser->as_string($dsn),
      'using methods', @$methods);

   my @replicas;
   METHOD:
   foreach my $method ( @$methods ) {
      my $find_replicas = "_find_replicas_by_$method";
      PTDEBUG && _d('Finding replicas with', $find_replicas);
      @replicas = $self->$find_replicas($dsn_parser, $dbh, $dsn);
      last METHOD if @replicas;
   }

   PTDEBUG && _d('Found', scalar(@replicas), 'replicas');
   return @replicas;
}

sub _find_replicas_by_processlist {
   my ( $self, $dsn_parser, $dbh, $dsn ) = @_;
   my @connected_replicas = $self->get_connected_replicas($dbh);
   my @replicas = $self->_process_replicas_list($dsn_parser, $dsn, \@connected_replicas);
   return @replicas;
}

sub _process_replicas_list {
   my ($self, $dsn_parser, $dsn, $connected_replicas) = @_;
   my @replicas = map  {
      my $replica        = $dsn_parser->parse("h=$_", $dsn);
      $replica->{source} = 'processlist';
      $replica;
   }
   grep { $_ }
   map  {
      my ( $host ) = $_->{host} =~ m/^(.*):\d+$/;
      if ( $host eq 'localhost' ) {
         $host = '127.0.0.1'; # Replication never uses sockets.
      }
      if ($host =~ m/::/) {
          $host = '['.$host.']';
      }
      $host;
   } @$connected_replicas;

   return @replicas;
}

# SHOW REPLICAS is significantly less reliable.
# Machines tend to share the host list around with every machine in the
# replication hierarchy, but they don't update each other when machines
# disconnect or change to use a different source or something.  So there is
# lots of cruft in SHOW REPLICAS.
sub _find_replicas_by_hosts {
   my ( $self, $dsn_parser, $dbh, $dsn ) = @_;

   my @replicas;

   my $vp = VersionParser->new($dbh);
   my $sql = 'SHOW REPLICAS';
   my $source_name = 'source';
   if ( $vp lt '8.1' || $vp->flavor() =~ m/maria/i ) {
      $sql = 'SHOW SLAVE HOSTS';
      $source_name='master';
   }
   
   PTDEBUG && _d($dbh, $sql);
   @replicas = @{$dbh->selectall_arrayref($sql, { Slice => {} })};

   # Convert SHOW REPLICAS into DSN hashes.
   if ( @replicas ) {
      PTDEBUG && _d('Found some SHOW REPLICAS info');
      @replicas = map {
         my %hash;
         @hash{ map { lc $_ } keys %$_ } = values %$_;
         my $spec = "h=$hash{host},P=$hash{port}"
            . ( $hash{user} ? ",u=$hash{user}" : '')
            . ( $hash{password} ? ",p=$hash{password}" : '');
         my $dsn           = $dsn_parser->parse($spec, $dsn);
         $dsn->{server_id} = $hash{server_id};
         $dsn->{source_id} = $hash{"${source_name}_id"};
         $dsn->{source}    = 'hosts';
         $dsn;
      } @replicas;
   }

   return @replicas;
}

# Returns PROCESSLIST entries of connected replicas, normalized to lowercase
# column names.
sub get_connected_replicas {
   my ( $self, $dbh ) = @_;

   # Check for the PROCESS privilege.
   my $sql = "SHOW GRANTS";
   PTDEBUG && _d($dbh, $sql);

   my $proc;
   eval {
      $proc = grep {
         m/ALL PRIVILEGES.*?\*\.\*|PROCESS/
      } @{$dbh->selectcol_arrayref($sql)};
   };
   
   die "Failed to $sql: $EVAL_ERROR" if $EVAL_ERROR;
   
   if ( !$proc ) {
      die "You do not have the PROCESS privilege";
   }

   $sql = 'SHOW FULL PROCESSLIST';
   PTDEBUG && _d($dbh, $sql);
   # It's probably a replica if it's doing a binlog dump.
   grep { $_->{command} =~ m/Binlog Dump/i }
   map  { # Lowercase the column names
      my %hash;
      @hash{ map { lc $_ } keys %$_ } = values %$_;
      \%hash;
   }
   @{$dbh->selectall_arrayref($sql, { Slice => {} })};
}

# Verifies that $source is really the source of $replica.  This is not an exact
# science, but there is a decent chance of catching some obvious cases when it
# is not the source.  If not the source, it dies; otherwise returns true.
sub is_source_of {
   my ( $self, $source, $replica ) = @_;

   my $source_name = get_source_name($replica);
   my $source_port = "${source_name}_port";

   my $source_status = $self->get_source_status($source)
      or die "The server specified as a source is not a source";
   my $replica_status  = $self->get_replica_status($replica)
      or die "The server specified as a replica is not a replica";
   my @connected     = $self->get_connected_replicas($source)
      or die "The server specified as a source has no connected replicas";
   my (undef, $port) = $source->selectrow_array("SHOW VARIABLES LIKE 'port'");

   if ( $port != $replica_status->{$source_port} ) {
      die "The replica is connected to $replica_status->{$source_port} "
         . "but the source's port is $port";
   }

   if ( !grep { $replica_status->{"${source_name}_user"} eq $_->{user} } @connected ) {
      die "I don't see any replica I/O thread connected with user "
         . $replica_status->{"${source_name}_user"};
   }

   if ( ( ($replica_status->{replica_io_state} || '')
         eq 'Waiting for source to send event' )
      || ( ($replica_status->{replica_io_state} || '')
         eq 'Waiting for master to send event' ) )
   {
      # The replica thinks its I/O thread is caught up to the source.  Let's
      # compare and make sure the source and replica are reasonably close to each
      # other.  Note that this is one of the few places where I check the I/O
      # thread positions instead of the SQL thread positions!
      # Source_Log_File/Read_Source_Log_Pos is the I/O thread's position on the
      # source.
      my ( $source_log_name, $source_log_num )
         = $source_status->{file} =~ m/^(.*?)\.0*([1-9][0-9]*)$/;
      my ( $replica_log_name, $replica_log_num )
         = $replica_status->{source_log_file} =~ m/^(.*?)\.0*([1-9][0-9]*)$/;
      if ( $source_log_name ne $replica_log_name
         || abs($source_log_num - $replica_log_num) > 1 )
      {
         die "The replica thinks it is reading from "
            . "$replica_status->{source_log_file},  but the "
            . "source is writing to $source_status->{file}";
      }
   }
   return 1;
}

# Figures out how to connect to the source, by examining SHOW REPLICA STATUS.  But
# does NOT use the value from Source_User for the username, because typically we
# want to perform operations as the username that was specified (usually to the
# program's --user option, or in a DSN), rather than as the replication user,
# which is often restricted.
sub get_source_dsn {
   my ( $self, $dbh, $dsn, $dsn_parser ) = @_;

   my $vp = VersionParser->new($dbh);
   my $source_host = 'source_host';
   my $source_port = 'source_port';
   if ( $vp lt '8.1' || $vp->flavor() =~ m/maria/i ) {
      $source_host = 'master_host';
      $source_port = 'master_port';
   }

   my $source = $self->get_replica_status($dbh) or return undef;
   my $spec   = "h=$source->{${source_host}},P=$source->{${source_port}}";
   return       $dsn_parser->parse($spec, $dsn);
}

# Gets SHOW REPLICA STATUS, with column names all lowercased, as a hashref.
sub get_replica_status {
   my ( $self, $dbh ) = @_;

   my $replica_name = get_replica_name($dbh);

   if ( !$self->{not_a_replica}->{$dbh} ) {
      my $sth = $self->{sths}->{$dbh}->{REPLICA_STATUS}
            ||= $dbh->prepare("SHOW ${replica_name} STATUS");
      PTDEBUG && _d($dbh, "SHOW ${replica_name} STATUS");
      $sth->execute();
      my ($sss_rows) = $sth->fetchall_arrayref({}); # Show Replica Status rows

      # If SHOW REPLICA STATUS returns more than one row it means that this replica is connected to more
      # than one source using replication channels.
      # If we have a channel name as a parameter, we need to select the correct row and return it.
      # If we don't have a channel name as a parameter, there is no way to know what the correct source is so,
      # return an error.
      my $ss;
      if ( $sss_rows && @$sss_rows ) {
          if (scalar @$sss_rows > 1) {
              if (!$self->{channel}) {
                  die 'This server returned more than one row for SHOW REPLICA STATUS but "channel" was not specified on the command line';
              }
              my $replica_use_channels;
              for my $row (@$sss_rows) {
                  $row = { map { lc($_) => $row->{$_} } keys %$row }; # lowercase the keys
                  if ($row->{channel_name}) {
                      $replica_use_channels = 1;
                  }
                  if ($row->{channel_name} eq $self->{channel}) {
                      $ss = $row;
                      last;
                  }
              }
              if (!$ss && $replica_use_channels) {
                 die 'This server is using replication channels but "channel" was not specified on the command line';
              }
          } else {
              if ($sss_rows->[0]->{channel_name} && $sss_rows->[0]->{channel_name} ne $self->{channel}) {
                  die 'This server is using replication channels but "channel" was not specified on the command line';
              } else {
                  $ss = $sss_rows->[0];
              }
          }

          if ( $ss && %$ss ) {
             $ss = { map { lc($_) => $ss->{$_} } keys %$ss }; # lowercase the keys
             return $ss;
          }
          if (!$ss && $self->{channel}) {
              die "Specified channel name is invalid";
          }
      }

      PTDEBUG && _d('This server returns nothing for SHOW REPLICA STATUS');
      $self->{not_a_replica}->{$dbh}++;
  }
}

# Gets SHOW BINARY LOGS, with column names all lowercased, as a hashref.
sub get_source_status {
   my ( $self, $dbh ) = @_;

   if ( $self->{not_a_source}->{$dbh} ) {
      PTDEBUG && _d('Server on dbh', $dbh, 'is not a source');
      return;
   }

   my $vp = VersionParser->new($dbh);
   my $source_name = 'binary log';
   if ( $vp lt '8.1' || $vp->flavor() =~ m/maria/i ) {
      $source_name = 'master';
   }

   my $sth;
   if ( $self->{sths}->{$dbh} && $dbh && $self->{sths}->{$dbh} == $dbh ) {
      $sth = $self->{sths}->{$dbh}->{SOURCE_STATUS}
         ||= $dbh->prepare("SHOW ${source_name} STATUS");
   }
   else {
      $sth = $dbh->prepare("SHOW ${source_name} STATUS");
   }
   PTDEBUG && _d($dbh, "SHOW ${source_name} STATUS");
   $sth->execute();
   my ($ms) = @{$sth->fetchall_arrayref({})};
   PTDEBUG && _d(
      $ms ? map { "$_=" . (defined $ms->{$_} ? $ms->{$_} : '') } keys %$ms
          : '');

   if ( !$ms || scalar keys %$ms < 2 ) {
      PTDEBUG && _d('Server on dbh', $dbh, 'does not seem to be a source');
      $self->{not_a_source}->{$dbh}++;
   }

  return { map { lc($_) => $ms->{$_} } keys %$ms }; # lowercase the keys
}

# Sub: wait_for_source
#   Execute SOURCE_POS_WAIT() to make replica wait for its source.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   * source_status - Hashref returned by <get_source_status()>
#   * replica_dbh     - dbh for replica host
#
# Optional Arguments:
#   * timeout - Wait time in seconds (default 60)
#
# Returns:
#   Hashref with result of waiting, like:
#   (start code)
#   {
#     result => the result returned by SOURCE_POS_WAIT: -1, undef, 0+
#     waited => the number of seconds waited, might be zero
#   }
#   (end code)
sub wait_for_source {
   my ( $self, %args ) = @_;
   my @required_args = qw(source_status replica_dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($source_status, $replica_dbh) = @args{@required_args};
   my $timeout       = $args{timeout} || 60;

   my $result;
   my $waited;
   if ( $source_status ) {
      my $replica_status;
      eval {
          $replica_status = $self->get_replica_status($replica_dbh);
      };
      if ($EVAL_ERROR) {
          return {
              result => undef,
              waited => 0,
              error  =>'Wait for source: this is a multi-source replica but "channel" was not specified on the command line',
          };
      }
      my $source_name = get_source_name($replica_dbh);
      my $vp = VersionParser->new($replica_dbh);
      my $channel_sql = $vp > '5.6' && $self->{channel} ? ", '$self->{channel}'" : '';
      my $sql = "SELECT ${source_name}_POS_WAIT('$source_status->{file}', $source_status->{position}, $timeout $channel_sql)";
      PTDEBUG && _d($replica_dbh, $sql);
      my $start = time;
      ($result) = $replica_dbh->selectrow_array($sql);

      # If SOURCE_POS_WAIT() returned NULL and we waited at least 1s
      # and the time we waited is less than the timeout then this is
      # a strong indication that the replica was stopped while we were
      # waiting.
      $waited = time - $start;

      PTDEBUG && _d('Result of waiting:', $result);
      PTDEBUG && _d("Waited", $waited, "seconds");
   }
   else {
      PTDEBUG && _d('Not waiting: this server is not a source');
   }

   return {
      result => $result,
      waited => $waited,
   };
}

# Executes STOP REPLICA.
sub stop_replica {
   my ( $self, $dbh ) = @_;
   my $replica_name = get_replica_name($dbh);

   my $sth = $self->{sths}->{$dbh}->{STOP_REPLICA}
         ||= $dbh->prepare("STOP ${replica_name}");
   PTDEBUG && _d($dbh, $sth->{Statement});
   $sth->execute();
}

# Executes START REPLICA, optionally with UNTIL.
sub start_replica {
   my ( $self, $dbh, $pos ) = @_;

   my $source_name = get_source_name($dbh);
   my $replica_name = get_replica_name($dbh);

   if ( $pos ) {
      # Just like with CHANGE REPLICATION SOURCE TO, you can't quote the position.
      my $sql = "START ${replica_name} UNTIL ${source_name}_LOG_FILE='$pos->{file}', "
              . "${source_name}_LOG_POS=$pos->{position}";
      PTDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }
   else {
      my $sth = $self->{sths}->{$dbh}->{START_REPLICA}
            ||= $dbh->prepare("START ${replica_name}");
      PTDEBUG && _d($dbh, $sth->{Statement});
      $sth->execute();
   }
}

# Waits for the replica to catch up to its source, using START REPLICA UNTIL.  When
# complete, the replica is caught up to the source, and the replica process is
# stopped on both servers.
sub catchup_to_source {
   my ( $self, $replica, $source, $timeout ) = @_;
   $self->stop_replica($source);
   $self->stop_replica($replica);
   my $replica_status  = $self->get_replica_status($replica);
   my $replica_pos     = $self->repl_posn($replica_status);
   my $source_status = $self->get_source_status($source);
   my $source_pos    = $self->repl_posn($source_status);
   PTDEBUG && _d('Source position:', $self->pos_to_string($source_pos),
      'Replica position:', $self->pos_to_string($replica_pos));

   my $result;
   if ( $self->pos_cmp($replica_pos, $source_pos) < 0 ) {
      PTDEBUG && _d('Waiting for replica to catch up to source');
      $self->start_replica($replica, $source_pos);

      # The replica may catch up instantly and stop, in which case
      # SOURCE_POS_WAIT will return NULL and $result->{result} will be undef.
      # We must catch this; if it returns NULL, then we check that
      # its position is as desired.
      # TODO: what if source_pos_wait times out and $result == -1? retry?
      $result = $self->wait_for_source(
            source_status => $source_status,
            replica_dbh   => $replica,
            timeout       => $timeout,
            source_status => $source_status
      );
      if ($result->{error}) {
          die $result->{error};
      }
      if ( !defined $result->{result} ) {
         $replica_status = $self->get_replica_status($replica);
            
         my $replica_name = get_replica_name($replica);

         if ( !$self->replica_is_running($replica_status, $replica_name) ) {
            PTDEBUG && _d('Source position:',
               $self->pos_to_string($source_pos),
               'Replica position:', $self->pos_to_string($replica_pos));
            $replica_pos = $self->repl_posn($replica_status);
            if ( $self->pos_cmp($replica_pos, $source_pos) != 0 ) {
               die "SOURCE_POS_WAIT() returned NULL but replica has not "
                  . "caught up to source";
            }
            PTDEBUG && _d('Replica is caught up to source and stopped');
         }
         else {
            die "Replica has not caught up to source and it is still running";
         }
      }
   }
   else {
      PTDEBUG && _d("Replica is already caught up to source");
   }

   return $result;
}

# Makes one server catch up to the other in replication.  When complete, both
# servers are stopped and at the same position.
sub catchup_to_same_pos {
   my ( $self, $s1_dbh, $s2_dbh ) = @_;
   $self->stop_replica($s1_dbh);
   $self->stop_replica($s2_dbh);
   my $s1_status = $self->get_replica_status($s1_dbh);
   my $s2_status = $self->get_replica_status($s2_dbh);
   my $s1_pos    = $self->repl_posn($s1_status);
   my $s2_pos    = $self->repl_posn($s2_status);
   if ( $self->pos_cmp($s1_pos, $s2_pos) < 0 ) {
      $self->start_replica($s1_dbh, $s2_pos);
   }
   elsif ( $self->pos_cmp($s2_pos, $s1_pos) < 0 ) {
      $self->start_replica($s2_dbh, $s1_pos);
   }

   # Re-fetch the replication statuses and positions.
   $s1_status = $self->get_replica_status($s1_dbh);
   $s2_status = $self->get_replica_status($s2_dbh);
   $s1_pos    = $self->repl_posn($s1_status);
   $s2_pos    = $self->repl_posn($s2_status);

   my $replica1_name = get_replica_name($s1_dbh);

   my $replica2_name = get_replica_name($s2_dbh);

   # Verify that they are both stopped and are at the same position.
   if ( $self->replica_is_running($s1_status, $replica1_name)
     || $self->replica_is_running($s2_status, $replica2_name)
     || $self->pos_cmp($s1_pos, $s2_pos) != 0)
   {
      die "The servers aren't both stopped at the same position";
   }

}

# Returns true if the replica is running.
sub replica_is_running {
   my ( $self, $replica_status, $replica_name ) = @_;
   return ($replica_status->{"${replica_name}_sql_running"} || 'No') eq 'Yes';
}

# Returns true if the server's log_replica_updates option is enabled.
sub has_replica_updates {
   my ( $self, $dbh ) = @_;
   
   my $replica_name = get_replica_name($dbh);

   my $sql = qq{SHOW VARIABLES LIKE 'log_${replica_name}_updates'};
   PTDEBUG && _d($dbh, $sql);
   my ($name, $value) = $dbh->selectrow_array($sql);
   return $value && $value =~ m/^(1|ON)$/;
}

# Extracts the replication position out of either SHOW REPLICATION SOURCE STATUS or SHOW
# REPLICA STATUS, and returns it as a hashref { file, position }
sub repl_posn {
   my ( $self, $status ) = @_;
   if ( exists $status->{file} && exists $status->{position} ) {
      # It's the output of SHOW BINARY LOG STATUS
      return {
         file     => $status->{file},
         position => $status->{position},
      };
   }
   elsif ( exists $status->{relay_source_log_file} && exists $status->{exec_source_log_pos} ) {
      # We are on MySQL 8.0.22+
      return {
         file     => $status->{relay_source_log_file},
         position => $status->{exec_source_log_pos},
      };
   }
   else {
      return {
         file     => $status->{relay_master_log_file},
         position => $status->{exec_master_log_pos},
      };
   }
}

# Gets the replica's lag.  TODO: permit using a heartbeat table.
sub get_replica_lag {
   my ( $self, $dbh ) = @_;
   
   my $source_name = get_source_name($dbh);

   my $stat = $self->get_replica_status($dbh);
   return unless $stat;  # server is not a replica
   return $stat->{"seconds_behind_${source_name}"};
}

# Compares two replication positions and returns -1, 0, or 1 just as the cmp
# operator does.
sub pos_cmp {
   my ( $self, $a, $b ) = @_;
   return $self->pos_to_string($a) cmp $self->pos_to_string($b);
}

# Sub: short_host
#   Simplify a hostname as much as possible.  For purposes of replication, a
#   hostname is really just the combination of hostname and port, since
#   replication always uses TCP connections (it does not work via sockets).  If
#   the port is the default 3306, it is omitted.  As a convenience, this sub
#   accepts either SHOW REPLICA STATUS or a DSN.
#
# Parameters:
#   $dsn - DSN hashref
#
# Returns:
#   Short hostname string
sub short_host {
   my ( $self, $dsn ) = @_;
   my ($host, $port);
   if ( $dsn->{source_host} ) {
      $host = $dsn->{source_host};
      $port = $dsn->{source_port};
   }
   else {
      $host = $dsn->{h};
      $port = $dsn->{P};
   }
   return ($host || '[default]') . ( ($port || 3306) == 3306 ? '' : ":$port" );
}

# Sub: is_replication_thread
#   Determine if a processlist item is a replication thread.
#
# Parameters:
#   $query - Hashref of a processlist item
#   %args  - Arguments
#
# Arguments:
#   type            - Which kind of repl thread to match:
#                     all, binlog_dump (source), replica_io, or replica_sql
#                     (default: all)
#   check_known_ids - Check known replication thread IDs (default: yes)
#
# Returns:
#   True if the proclist item is the given type of replication thread.
sub is_replication_thread {
   my ( $self, $query, %args ) = @_;
   return unless $query;

   my $type = lc($args{type} || 'all');
   die "Invalid type: $type"
      unless $type =~ m/^binlog_dump|slave_io|slave_sql|replica_io|replica_sql|all$/i;

   my $match = 0;
   if ( $type =~ m/binlog_dump|all/i ) {
      $match = 1
         if ($query->{Command} || $query->{command} || '') eq "Binlog Dump";
   }
   if ( !$match ) {
      # On a replica, there are two threads.  Both have user="system user".
      if ( ($query->{User} || $query->{user} || '') eq "system user" ) {
         PTDEBUG && _d("Replica replication thread");
         if ( $type ne 'all' ) {
            # Match a particular replica thread.
            my $state = $query->{State} || $query->{state} || '';

            if ( $state =~ m/^init|end$/ ) {
               # http://code.google.com/p/maatkit/issues/detail?id=1121
               PTDEBUG && _d("Special state:", $state);
               $match = 1;
            }
            else {
               # These patterns are abbreviated because if the first few words
               # match chances are very high it's the full replica thd state.
               my ($replica_sql) = $state =~ m/
                  ^(Waiting\sfor\sthe\snext\sevent
                   |Reading\sevent\sfrom\sthe\srelay\slog
                   |Has\sread\sall\srelay\slog;\swaiting
                   |Making\stemp\sfile
                   |Waiting\sfor\sslave\smutex\son\sexit
                   |Waiting\sfor\sreplica\smutex\son\sexit)/xi;

               # Type is either "replica_sql" or "replica_io".  The second line
               # implies that if this isn't the sql thread then it must be
               # the io thread, so match is true if we were supposed to match
               # the io thread.
               $match = $type eq 'replica_sql' &&  $replica_sql ? 1
                      : $type eq 'replica_io'  && !$replica_sql ? 1
                      :                                       0;
            }
         }
         else {
            # Type is "all" and it's not a source (binlog_dump) thread,
            # else we wouldn't have gotten here.  It's either of the 2
            # replica threads and we don't care which.
            $match = 1;
         }
      }
      else {
         PTDEBUG && _d('Not system user');
      }

      # MySQL loves to trick us.  Sometimes a replica replication thread will
      # temporarily morph into what looks like a regular user thread when
      # really it's still the same replica repl thread.  So here we save known
      # repl thread IDs and check if a non-matching event is actually a
      # known repl thread ID and if yes then we make it match.
      if ( !defined $args{check_known_ids} || $args{check_known_ids} ) {
         my $id = $query->{Id} || $query->{id};
         if ( $match ) {
            $self->{replication_thread}->{$id} = 1;
         }
         else {
            if ( $self->{replication_thread}->{$id} ) {
               PTDEBUG && _d("Thread ID is a known replication thread ID");
               $match = 1;
            }
         }
      }
   }

   PTDEBUG && _d('Matches', $type, 'replication thread:',
      ($match ? 'yes' : 'no'), '; match:', $match);

   return $match;
}


# Sub: get_replication_filters
#   Get any replication filters set on the host.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dbh - dbh, source or replica
#
# Returns:
#   Hashref of any replication filters.  If none are set, an empty hashref
#   is returned.
sub get_replication_filters {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh) = @args{@required_args};

   my $replica_name = get_replica_name($dbh);

   my %filters = ();

   my $status = $self->get_source_status($dbh);
   if ( $status ) {
      map { $filters{$_} = $status->{$_} }
      grep { defined $status->{$_} && $status->{$_} ne '' }
      qw(
         binlog_do_db
         binlog_ignore_db
      );
   }

   $status = $self->get_replica_status($dbh);
   if ( $status ) {
      map { $filters{$_} = $status->{$_} }
      grep { defined $status->{$_} && $status->{$_} ne '' }
      qw(
         replicate_do_db
         replicate_ignore_db
         replicate_do_table
         replicate_ignore_table
         replicate_wild_do_table
         replicate_wild_ignore_table
      );

      my $sql = "SHOW VARIABLES LIKE '${replica_name}_skip_errors'";
      PTDEBUG && _d($dbh, $sql);
      my $row = $dbh->selectrow_arrayref($sql);
      # "OFF" in 5.0, "" in 5.1
      $filters{replica_skip_errors} = $row->[1] if $row->[1] && $row->[1] ne 'OFF';
   }

   return \%filters;
}


# Sub: pos_to_string
#   Stringify a position in a way that's string-comparable.
#
# Parameters:
#   $pos - Hashref with file and position
#
# Returns:
#   String like "file/posNNNNN"
sub pos_to_string {
   my ( $self, $pos ) = @_;
   my $fmt  = '%s/%020d';
   return sprintf($fmt, @{$pos}{qw(file position)});
}

sub reset_known_replication_threads {
   my ( $self ) = @_;
   $self->{replication_thread} = {};
   return;
}

sub get_cxn_from_dsn_table {
   my ($self, %args) = @_;
   my @required_args = qw(dsn_table_dsn make_cxn parent);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dsn_table_dsn, $make_cxn, $parent) = @args{@required_args};
   PTDEBUG && _d('DSN table DSN:', $dsn_table_dsn);

   my $dp = $self->{DSNParser};
   my $q  = $self->{Quoter};

   my $dsn = $dp->parse($dsn_table_dsn);
   my $dsn_table;
   if ( $dsn->{D} && $dsn->{t} ) {
      $dsn_table = $q->quote($dsn->{D}, $dsn->{t});
   }
   elsif ( $dsn->{t} && $dsn->{t} =~ m/\./ ) {
      $dsn_table = $q->quote($q->split_unquote($dsn->{t}));
   }
   else {
      die "DSN table DSN does not specify a database (D) "
        . "or a database-qualified table (t)";
   }

   my $done = 0;
   my $dsn_tbl_cxn = $make_cxn->(dsn => $dsn);
   my $dbh         = $dsn_tbl_cxn->connect();
   my $sql         = "SELECT dsn FROM $dsn_table ORDER BY id";
   PTDEBUG && _d($sql);
   my @cxn;
   use Data::Dumper;
   DSN:
   do {
      @cxn = ();
      my $dsn_strings = $dbh->selectcol_arrayref($sql);
      if ( $dsn_strings ) {
         foreach my $dsn_string ( @$dsn_strings ) {
            PTDEBUG && _d('DSN from DSN table:', $dsn_string);
            if ($args{wait_no_die}) {
               my $lcxn;
               eval {
                  $lcxn = $make_cxn->(dsn_string => $dsn_string);
               };
               if ( $EVAL_ERROR && ($dsn_tbl_cxn->lost_connection($EVAL_ERROR)
                     || $EVAL_ERROR =~ m/Can't connect to MySQL server/)) {
                  PTDEBUG && _d("Server is not accessible, waiting when it is online again");
                  sleep(1);
                  goto DSN;
               }
               push @cxn, $lcxn;
            } else {
               push @cxn, $make_cxn->(dsn_string => $dsn_string, parent => $parent);
            }
         }
      }
      $done = 1;
   } until $done;
   return \@cxn;
}

sub get_source_name {
   my ($dbh) = @_;
   my $vp = VersionParser->new($dbh);
   return ($vp lt '8.1' || $vp->flavor() =~ m/maria/i) ? 'master' : 'source';
}

sub get_replica_name {
   my ($dbh) = @_;
   my $vp = VersionParser->new($dbh);
   return ($vp lt '8.1' || $vp->flavor() =~ m/maria/i) ? 'slave' : 'replica';
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
# End MasterSlave package
# ###########################################################################
