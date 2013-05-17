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
package Percona::Agent::Logger;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use JSON;
use threads;
use Thread::Queue;

use Lmo;
use Transformers;
use Percona::WebAPI::Resource::LogEntry;

Transformers->import(qw(ts));

has 'level' => (
   is       => 'rw',
   isa      => 'Int',
   required => 0,
   default  => sub { return 1; },  # info
);

has 'client' => (
   is       => 'rw',
   isa      => 'Object',
   required => 0,
);

has 'log_link' => (
   is       => 'rw',
   isa      => 'Str',
   required => 0,
);

has 'exit_status' => (
   is       => 'rw',
   isa      => 'ScalarRef',
   required => 1,
);

has '_message_queue' => (
   is       => 'rw',
   isa      => 'Object',
   required => 0,
);

has '_thread' => (
   is       => 'rw',
   isa      => 'Object',
   required => 0,
);

has 'online_logging' => (
   is       => 'rw',
   isa      => 'Bool',
   required => 0,
   default  => sub { return 0 },
);

sub enable_online_logging {
   my ($self, %args) = @_;
   my $client   = $args{client};
   my $log_link = $args{log_link};

   $self->_message_queue(Thread::Queue->new());

   $self->_thread(
      threads::async {
         my @log_entries;
         my $oktorun = 1;
         QUEUE:
         while ( $oktorun ) {
            my $max_log_entries = 1_000;  # for each POST + backlog
            while (    $self->_message_queue
                    && $self->_message_queue->pending()
                    && $max_log_entries--
                    && (my $entry = $self->_message_queue->dequeue()) )
            {
               $oktorun = 0 if !defined $entry;
               # $event = [ level, "message" ]
               push @log_entries, Percona::WebAPI::Resource::LogEntry->new(
                  log_level => $entry->[0],
                  message   => $entry->[1],
               );
            }
            if ( scalar @log_entries ) { 
               eval {
                  $client->post(
                     link      => $log_link,
                     resources => \@log_entries,
                  );
               };
               if ( my $e = $EVAL_ERROR ) {
                  warn "$e";
               }
               else {
                  @log_entries = ();
               }
            }  # have log entries
            sleep ($self->_message_queue ? 3 : 5);
         }  # QUEUE
      }  # threads::async
   );

   $self->online_logging(1);

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

sub debug {
   my $self = shift;
   return unless $self->level >= 1;
   return $self->_log('DEBUG', @_);
}

sub info {
   my $self = shift;
   return unless $self->level >= 2;
   return $self->_log('INFO', @_);
}

sub warn {
   my $self = shift;
   $self->_set_exit_status();
   return unless $self->level >= 3;
   return $self->_log('WARNING', @_);
}

sub error {
   my $self = shift;
   $self->_set_exit_status();
   return unless $self->level >= 4;
   return $self->_log('ERROR', @_);
}

sub fatal {
   my $self = shift;
   $self->_set_exit_status();
   $self->_log('FATAL', @_);
   exit $self->exit_status;
}

sub _set_exit_status {
   my $self = shift;
   # exit_status is a scalar ref
   my $exit_status = $self->exit_status;  # get ref
   $$exit_status |= 1;                    # deref to set
   $self->exit_status($exit_status);      # save back ref
   return;
}

sub _log {
   my ($self, $level, $msg) = @_;
   chomp($msg);
   my $ts = ts(time, 1);  # 1=UTC
   my $level_number = level_number($level);
   if ( $level_number >= 3 ) {  # warning
      print STDERR "$ts $level $msg\n";
   }
   else {
      print "$ts $level $msg\n";
   }
   if ( $self->online_logging ) {
      my @event :shared = ($level_number, $msg);
      $self->_message_queue->enqueue(\@event);
   }
   return;
}

sub DESTROY {
   my $self = shift;
   if ( $self->_message_queue ) {
      $self->_message_queue->enqueue(undef);  # stop thread's while loop
      $self->_thread->join();
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

no Lmo;
1;
# ###########################################################################
# End Percona::Agent::Logger package
# ###########################################################################
