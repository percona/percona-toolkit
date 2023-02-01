# This program is copyright 2011 Percona Ireland Ltd.
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
# Cxn package
# ###########################################################################
{
# Package: Cxn
# Cxn creates and properly initializes a MySQL connection.  This class
# encapsulates connections for several reasons.  One, initialization
# may involve setting or changing several things, so centralizing this
# guarantees that each cxn is properly and consistently initialized.
# Two, the class's deconstructor (DESTROY) ensures that each cxn is
# disconnected even if the program dies unexpectedly.  Three, when a cxn
# is lost and re-connected, accessing the dbh via the sub dbh() instead
# of via the var $dbh ensures that the program always uses the new, correct
# dbh.  Four, by encapsulating a cxn with subs that manage that cxn,
# the receiver of a Cxn obj can re-connect the cxn if it's lost without
# knowing how that's done (and it shouldn't know; that's not its job).
package Cxn;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Scalar::Util qw(blessed);
use constant {
   PTDEBUG => $ENV{PTDEBUG} || 0,
   # Hostnames make testing less accurate.  Tests need to see
   # that such-and-such happened on specific slave hosts, but
   # the sandbox servers are all on one host so all slaves have
   # the same hostname.
   PERCONA_TOOLKIT_TEST_USE_DSN_NAMES => $ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} || 0,
};

# Sub: new
#
# Required Arguments:
#   DSNParser    - <DSNParser> object
#   dsn          - DSN hashref, or...
#   dsn_string   - ... DSN string like "h=127.1,P=12345"
#
# Optional Arguments:
#   dbh - Pre-created, uninitialized dbh
#   set - Callback to set vars on dbh when dbh is first connected
# 
# Returns:
#   Cxn object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(DSNParser OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my ($dp, $o) = @args{@required_args};

   # Any tool that connects to MySQL should have a standard set of
   # connection options like --host, --port, --user, etc.  These
   # are default values; they're used in the DSN if the DSN doesn't
   # explicate the corresponding part (h=--host, P=--port, etc.).
   my $dsn_defaults = $dp->parse_options($o);
   my $prev_dsn     = $args{prev_dsn};
   my $dsn          = $args{dsn};
   if ( !$dsn ) {
      # If there's no DSN and no DSN string, then the user probably ran
      # the tool without specifying a DSN or any default connection options.
      # They're probably relying on DBI/DBD::mysql to do the right thing
      # by connecting to localhost.  On many systems, connecting just to
      # localhost causes DBI to use a built-in socket, i.e. it doesn't
      # always equate to 'h=127.0.0.1,P=3306'.
      $args{dsn_string} ||= 'h=' . ($dsn_defaults->{h} || 'localhost');

      $dsn = $dp->parse(
         $args{dsn_string}, $prev_dsn, $dsn_defaults);
   }
   elsif ( $prev_dsn ) {
      # OptionParser doesn't make DSN type options inherit values from
      # a command line DSN because it doesn't know which ARGV from the
      # command line are DSNs or other things.  So if the caller wants
      # DSNs to inherit values from a prev DSN (i.e. one from the
      # command line), then they must pass it as the prev_dsn and we
      # copy values from it into this new DSN, resulting in a new DSN
      # with values from both sources.
      $dsn = $dp->copy($prev_dsn, $dsn);
   }

   my $dsn_name = $dp->as_string($dsn, [qw(h P S)])
               || $dp->as_string($dsn, [qw(F)])
               || '';

   my $self = {
      dsn             => $dsn,
      dbh             => $args{dbh},
      dsn_name        => $dsn_name,
      hostname        => '',
      set             => $args{set},
      NAME_lc         => defined($args{NAME_lc}) ? $args{NAME_lc} : 1,
      dbh_set         => 0,
      ask_pass        => $o->get('ask-pass'),
      DSNParser       => $dp,
      is_cluster_node => undef,
      parent          => $args{parent},
   };

   return bless $self, $class;
}

sub connect {
   my ( $self, %opts ) = @_;
   my $dsn = $opts{dsn} || $self->{dsn};
   my $dp  = $self->{DSNParser};

   my $dbh = $self->{dbh};
   if ( !$dbh || !$dbh->ping() ) {
      # Ask for password once.
      if ( $self->{ask_pass} && !$self->{asked_for_pass} && !defined $dsn->{p} ) {
         $dsn->{p} = OptionParser::prompt_noecho("Enter MySQL password: ");
         $self->{asked_for_pass} = 1;
      }
      $dbh = $dp->get_dbh(
         $dp->get_cxn_params($dsn),
         {
            AutoCommit => 1,
            %opts,
         },
      );
   }

   $dbh = $self->set_dbh($dbh);
   if ( $opts{dsn} ) {
      $self->{dsn}      = $dsn;
      $self->{dsn_name} = $dp->as_string($dsn, [qw(h P S)])
                       || $dp->as_string($dsn, [qw(F)])
                       || '';

   }
   PTDEBUG && _d($dbh, 'Connected dbh to', $self->{hostname},$self->{dsn_name});
   return $dbh;
}

sub set_dbh {
   my ($self, $dbh) = @_;

   # If we already have a dbh, and that dbh is the same as this dbh,
   # and the dbh has already been set, then do not re-set the same
   # dbh.  dbh_set is required so that if this obj was created with
   # a dbh, we set that dbh when connect() is called because whoever
   # created the dbh probably didn't set what we set here.  For example,
   # MasterSlave makes dbhs when finding slaves, but it doesn't set
   # anything.
   if ( $self->{dbh} && $self->{dbh} == $dbh && $self->{dbh_set} ) {
      PTDEBUG && _d($dbh, 'Already set dbh');
      return $dbh;
   }

   PTDEBUG && _d($dbh, 'Setting dbh');

   # Set stuff for this dbh (i.e. initialize it).
   $dbh->{FetchHashKeyName} = 'NAME_lc' if $self->{NAME_lc};

   # Update the cxn's name.  Until we connect, the DSN parts
   # h and P are used.  Once connected, use @@hostname.
   my $sql = 'SELECT @@server_id /*!50038 , @@hostname*/';
   PTDEBUG && _d($dbh, $sql);
   my ($server_id, $hostname) = $dbh->selectrow_array($sql);
   PTDEBUG && _d($dbh, 'hostname:', $hostname, $server_id);
   if ( $hostname ) {
      $self->{hostname} = $hostname;
   }

   if ( $self->{parent} ) {
      PTDEBUG && _d($dbh, 'Setting InactiveDestroy=1 in parent');
      $dbh->{InactiveDestroy} = 1;
   }

   # Call the set callback to let the caller SET any MySQL variables.
   if ( my $set = $self->{set}) {
      $set->($dbh);
   }

   $self->{dbh}     = $dbh;
   $self->{dbh_set} = 1;
   return $dbh;
}

sub lost_connection {
   my ($self, $e) = @_;
   return 0 unless $e;
   return $e =~ m/MySQL server has gone away/
       || $e =~ m/Lost connection to MySQL server/
       || $e =~ m/Server shutdown in progress/;
      # The 1st pattern means that MySQL itself died or was stopped.
      # The 2nd pattern means that our cxn was killed (KILL <id>).
      # The 3rd pattern means MySQL is about to shut down.
}

# Sub: dbh
#   Return the cxn's dbh.
sub dbh {
   my ($self) = @_;
   return $self->{dbh};
}

# Sub: dsn
#   Return the cxn's dsn.
sub dsn {
   my ($self) = @_;
   return $self->{dsn};
}

# Sub: name
#   Return the cxn's name.
sub name {
   my ($self) = @_;
   return $self->{dsn_name} if PERCONA_TOOLKIT_TEST_USE_DSN_NAMES;
   return $self->{hostname} || $self->{dsn_name} || 'unknown host';
}

sub description {
   my ($self) = @_;
   return sprintf("%s -> %s:%s", $self->name(), $self->{dsn}->{h} || 'localhost' , $self->{dsn}->{P} || 'socket');
}

# This returns the server_id. 
# For cluster nodes, since server_id is unreliable, we use a combination of 
# variables to create an id string that is unique.
sub get_id {
   my ($self, $cxn) = @_;

   $cxn ||= $self;

   my $unique_id;
   if ($cxn->is_cluster_node()) {  # for cluster we concatenate various variables to maximize id 'uniqueness' across versions
      my $sql  = q{SHOW STATUS LIKE 'wsrep\_local\_index'};
      my (undef, $wsrep_local_index) = $cxn->dbh->selectrow_array($sql);
      PTDEBUG && _d("Got cluster wsrep_local_index: ",$wsrep_local_index);
      $unique_id = $wsrep_local_index."|"; 
      foreach my $val ('server\_id', 'wsrep\_sst\_receive\_address', 'wsrep\_node\_name', 'wsrep\_node\_address') {
         my $sql = "SHOW VARIABLES LIKE '$val'";
         PTDEBUG && _d($cxn->name, $sql);
         my (undef, $val) = $cxn->dbh->selectrow_array($sql);
         $unique_id .= "|$val";
      }
   } else {
      my $sql  = 'SELECT @@SERVER_ID';
      PTDEBUG && _d($sql);
      $unique_id = $cxn->dbh->selectrow_array($sql);
   }
   PTDEBUG && _d("Generated unique id for cluster:", $unique_id);
   return $unique_id;
}


# This is used to help remove_duplicate_cxns detect cluster nodes
# (which often have unreliable server_id's)
sub is_cluster_node {
   my ($self, $cxn) = @_;

   $cxn ||= $self;

   my $sql = "SHOW VARIABLES LIKE 'wsrep\_on'";

   # here we check if a DBI object was passed instead if a Cxn
   # just a convenience for tools that don't use a proper Cxn
   my $dbh;
   if ($cxn->isa('DBI::db')) {
      $dbh = $cxn;
      PTDEBUG && _d($sql); #don't invoke name() if it's not a Cxn!
   }
   else {
      $dbh = $cxn->dbh();      
      PTDEBUG && _d($cxn->name, $sql);
   }

   my $row = $dbh->selectrow_arrayref($sql);
   return $row && $row->[1] && ($row->[1] eq 'ON' || $row->[1] eq '1') ? 1 : 0;

}

# There's two reasons why there might be dupes:
# If the "master" is a cluster node, then a DSN table might have been
# used, and it may have all nodes' DSNs so the user can run the tool
# on any node, in which case it has the "master" node, the DSN given
# on the command line.
# On the other hand, maybe find_cluster_nodes worked, in which case
# we definitely have a dupe for the master cxn, but we may also have a
# dupe for every other node if this was used in conjunction with a
# DSN table.
# So try to detect and remove those.
sub remove_duplicate_cxns {
   my ($self, %args) = @_;
   my @cxns     = @{$args{cxns}};
   my $seen_ids = $args{seen_ids} || {};
   PTDEBUG && _d("Removing duplicates from ", join(" ", map { $_->name } @cxns));
   my @trimmed_cxns;

   for my $cxn ( @cxns ) {

      my $id = $cxn->get_id();
      PTDEBUG && _d('Server ID for ', $cxn->name, ': ', $id);

      if ( ! $seen_ids->{$id}++ ) {
         push @trimmed_cxns, $cxn
      }
      else {
         PTDEBUG && _d("Removing ", $cxn->name,
                       ", ID ", $id, ", because we've already seen it");
      }
   }

   return \@trimmed_cxns;
}

sub DESTROY {
   my ($self) = @_;

   PTDEBUG && _d('Destroying cxn');

   if ( $self->{parent} ) {
      PTDEBUG && _d($self->{dbh}, 'Not disconnecting dbh in parent');
   }
   elsif ( $self->{dbh}
           && blessed($self->{dbh})
           && $self->{dbh}->can("disconnect") )
   {
      PTDEBUG && _d($self->{dbh}, 'Disconnecting dbh on', $self->{hostname},
         $self->{dsn_name});
      $self->{dbh}->disconnect();
   }

   return;
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
# End Cxn package
# ###########################################################################
