# This program is copyright 2011 Percona Inc.
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
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

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

   my $dsn = $args{dsn};
   if ( !$dsn ) {
      # If there's no DSN and no DSN string, then the user probably ran
      # the tool without specifying a DSN or any default connection options.
      # They're probably relying on DBI/DBD::mysql to do the right thing
      # by connecting to localhost.  On many systems, connecting just to
      # localhost causes DBI to use a built-in socket, i.e. it doesn't
      # always equate to 'h=127.0.0.1,P=3306'.
      $args{dsn_string} ||= 'h=' . ($dsn_defaults->{h} || 'localhost');

      $dsn = $dp->parse(
         $args{dsn_string}, $args{prev_dsn}, $dsn_defaults);
   }

   my $self = {
      dsn          => $dsn,
      dbh          => $args{dbh},
      set          => $args{set},
      OptionParser => $o,
      DSNParser    => $dp,
   };

   MKDEBUG && _d('New connection to', $dsn->{n});
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
      MKDEBUG && _d('Connected dbh', $dbh, $dsn->{n});
   }

   return $self->set_dbh($dbh);
}

sub set_dbh {
   my ($self, $dbh) = @_;

   # Don't set stuff twice on the same dbh.
   return $dbh if $self->{dbh} && $self->{dbh} == $dbh;

   # Set stuff for this dbh (i.e. initialize it).
   $dbh->{FetchHashKeyName} = 'NAME_lc';

   if ( my $set = $self->{set}) {
      $set->($dbh);
   }

   $self->{dbh} = $dbh;
   return $dbh;
}

sub dbh {
   my ($self) = @_;
   return $self->{dbh};
}

sub dsn {
   my ($self) = @_;
   return $self->{dsn};
}

sub DESTROY {
   my ($self) = @_;
   if ( $self->{dbh} ) {
      MKDEBUG && _d('Disconnecting dbh', $self->{dbh}, $self->{dsn}->{n});
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
