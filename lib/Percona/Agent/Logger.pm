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

has 'queue_wait' => (
   is       => 'rw',
   isa      => 'Int',
   required => 0,
   default  => sub { return 3; },
);

has 'service' => (
   is       => 'ro',
   isa      => 'Str',
   required => 0,
);

has 'data_ts' => (
   is       => 'ro',
   isa      => 'Int',
   required => 0,
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
               # $entry = [ ts, level, "message" ]
               if ( defined $entry->[0] ) {
                  push @log_entries, Percona::WebAPI::Resource::LogEntry->new(
                     entry_ts  => $entry->[0],
                     log_level => $entry->[1],
                     message   => $entry->[2],
                     ($self->service ? (service => $self->service) : ()),
                     ($self->data_ts ? (data_ts => $self->data_ts) : ()),
                  );
               }
               else {
                  # Got "stop" entry: [ undef, undef, undef ]
                  $oktorun = 0;
               }
            }  # read log entries from queue

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

            if ( $oktorun ) {
               sleep $self->queue_wait;
            }
         }  # QUEUE oktorun

         if ( scalar @log_entries ) {
            my $ts = ts(time, 0);  # 0=local time
            warn "$ts WARNING Failed to send these log entries (timestamps are UTC):\n";
            foreach my $entry ( @log_entries ) {
               warn sprintf("%s %s %s\n", $entry->[0], level_name($entry->[1]), $entry->[2]);
            }
         }

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
   $self->_set_exit_status();
   return $self->_log('WARNING', @_);
}

sub error {
   my $self = shift;
   $self->_set_exit_status();
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
   
   my @event :shared = ($ts, $level_number, $msg);
   $self->_message_queue->enqueue(\@event);

   if ( !$self->online_logging ) {
      my $ts = ts(time, 0);  # 0=local time
      if ( $level_number >= 3 ) {  # warning
         print STDERR "$ts $level $msg\n";
      }
      else {
         print "$ts $level $msg\n";
      }
   }

   return;
}

sub DESTROY {
   my $self = shift;
   if ( $self->_thread && $self->_thread->is_running() ) {
      my @stop :shared = (undef, undef);
      $self->_message_queue->enqueue(\@stop);  # stop the thread
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
