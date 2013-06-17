# This program is copyright 2013 Percona Ireland Ltd.
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
# Percona::Agent::Logger package
# ###########################################################################
package Percona::Test::Mock::AgentLogger;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ($class, %args) = @_;
   my $self = {
      log            => $args{log},

      exit_status    => $args{exit_status},
      pid            => $args{pid},
      online_logging => $args{online_logging},

      service        => undef,
      data_ts        => undef,
      quiet          => 0,

   };
   return bless $self, $class;
}

sub service {
   my $self = shift;
   my $_service = shift;
   $self->{service} = $_service if $_service;
   return $self->{service};
}

sub data_ts {
   my $self = shift;
   my $_data_ts = shift;
   $self->{data_ts} = $_data_ts if $_data_ts;
   return $self->{data_ts};
}

sub quiet {
   my $self = shift;
   my $_quiet = shift;
   $self->{quiet} = $_quiet if $_quiet;
   return $self->{quiet};
}

sub start_online_logging {
   my ($self, %args) = @_;
   $self->_log('-', 'Called start_online_logging()');
   return;
}

sub level_number {
   my $name = shift;
   die "No log level name given" unless $name;
   my $number = $name eq 'DEBUG'   ? 1
              : $name eq 'INFO'    ? 2
              : $name eq 'WARNING' ? 3
              : $name eq 'ERROR'   ? 4
              : $name eq 'FATAL'   ? 5
              : die "Invalid log level name: $name";
}

sub level_name {
   my $number = shift;
   die "No log level name given" unless $number;
   my $name = $number == 1 ? 'DEBUG'
            : $number == 2 ? 'INFO'
            : $number == 3 ? 'WARNING'
            : $number == 4 ? 'ERROR'
            : $number == 5 ? 'FATAL'
            : die "Invalid log level number: $number";
}

sub debug {
   my $self = shift;
   return $self->_log('DEBUG', @_);
}

sub info {
   my $self = shift;
   return $self->_log('INFO', @_);
}

sub warning {
   my $self = shift;
   return $self->_log('WARNING', @_);
}

sub error {
   my $self = shift;
   return $self->_log('ERROR', @_);
}

sub fatal {
   my $self = shift;
   $self->_log('FATAL', @_);
   return 255;
}

sub _log {
   my ($self, $level, $msg) = @_;
   push @{$self->{log}}, "$level $msg";
   return;
}

1;
# ###########################################################################
# End Percona::Test::Mock::AgentLogger package
# ###########################################################################
