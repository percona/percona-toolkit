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
# Cxn creates a connection to MySQL and initializes it properly.
package Cxn;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(DSNParser OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   die "I need a dsn or dsn_string argument"
      unless $args{dsn} || $args{dsn_string};
   my ($dp, $o) = @args{@required_args};

   my $dsn = $args{dsn};
   if ( !$dsn ) {
      $dsn = $dp->parse(
         $args{dsn_string}, $args{prev_dsn}, $dp->parse_options($o));
   }

   my $self = {
      dsn_string   => $args{dsn_string},
      dsn          => $dsn,
      dbh          => $args{dbh},
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
   if ( !$dbh ) {
      if ( $o->get('ask-pass') ) {
         $dsn->{p} = OptionParser::prompt_noecho("Enter password: ");
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
