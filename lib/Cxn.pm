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
#   OptionParser - <OptionParser> object
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

   my $self = {
      dsn          => $dsn,
      dbh          => $args{dbh},
      dsn_name     => $dp->as_string($dsn, [qw(h P S)]),
      hostname     => '',
      set          => $args{set},
      NAME_lc      => defined($args{NAME_lc}) ? $args{NAME_lc} : 1,
      dbh_set      => 0,
      OptionParser => $o,
      DSNParser    => $dp,
      is_cluster_node => undef,
   };

   return bless $self, $class;
}

sub connect {
   my ( $self ) = @_;
   my $dsn = $self->{dsn};
   my $dp  = $self->{DSNParser};
   my $o   = $self->{OptionParser};

   my $dbh = $self->{dbh};
   if ( !$dbh || !$dbh->ping() ) {
      # Ask for password once.
      if ( $o->get('ask-pass') && !$self->{asked_for_pass} ) {
         $dsn->{p} = OptionParser::prompt_noecho("Enter MySQL password: ");
         $self->{asked_for_pass} = 1;
      }
      $dbh = $dp->get_dbh($dp->get_cxn_params($dsn),  { AutoCommit => 1 });
   }
   PTDEBUG && _d($dbh, 'Connected dbh to', $self->{name});

   return $self->set_dbh($dbh);
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

   # Call the set callback to let the caller SET any MySQL variables.
   if ( my $set = $self->{set}) {
      $set->($dbh);
   }

   $self->{dbh}     = $dbh;
   $self->{dbh_set} = 1;
   return $dbh;
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

sub DESTROY {
   my ($self) = @_;
   if ( $self->{dbh}
         && blessed($self->{dbh})
         && $self->{dbh}->can("disconnect") ) {
      PTDEBUG && _d('Disconnecting dbh', $self->{dbh}, $self->{name});
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
