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

use POSIX qw(SIGALRM);

use Lmo;
use Transformers;
use Percona::WebAPI::Resource::LogEntry;

Transformers->import(qw(ts));

has 'exit_status' => (
   is       => 'rw',
   isa      => 'ScalarRef',
   required => 1,
);

has 'pid' => (
   is       => 'ro',
   isa      => 'Int',
   required => 1,
);

has 'service' => (
   is       => 'rw',
   isa      => 'Maybe[Str]',
   required => 0,
   default  => sub { return; },
);

has 'data_ts' => (
   is       => 'rw',
   isa      => 'Maybe[Int]',
   required => 0,
   default  => sub { return; },
);

has 'online_logging' => (
   is       => 'ro',
   isa      => 'Bool',
   required => 0,
   default  => sub { return 1 },
);

has 'online_logging_enabled' => (
   is       => 'rw',
   isa      => 'Bool',
   required => 0,
   default  => sub { return 0 },
);

has 'quiet' => (
   is       => 'rw',
   isa      => 'Int',
   required => 0,
   default  => sub { return 0 },
);

has '_buffer' => (
   is       => 'rw',
   isa      => 'ArrayRef',
   required => 0,
   default  => sub { return []; },
);

has '_pipe_write' => (
   is       => 'rw',
   isa      => 'Maybe[FileHandle]',
   required => 0,
);

sub read_stdin {
   my ( $t ) = @_;

   # Set the SIGALRM handler.
   POSIX::sigaction(
      SIGALRM,
      POSIX::SigAction->new(sub { die 'read timeout'; }),
   ) or die "Error setting SIGALRM handler: $OS_ERROR";

   my $timeout = 0;
   my @lines;
   eval {
      alarm $t;
      while(defined(my $line = <STDIN>)) {
         push @lines, $line;
      }
      alarm 0;
   };
   if ( $EVAL_ERROR ) {
      PTDEBUG && _d('Read error:', $EVAL_ERROR);
      die $EVAL_ERROR unless $EVAL_ERROR =~ m/read timeout/;
      $timeout = 1;
   }
   return unless scalar @lines || $timeout;
   return \@lines;
}

sub start_online_logging {
   my ($self, %args) = @_;
   my $client       = $args{client};
   my $log_link     = $args{log_link};
   my $read_timeout = $args{read_timeout} || 3;

   return unless $self->online_logging;

   my $pid = open(my $pipe_write, "|-");

   if ($pid) {
      # parent
      select $pipe_write;
      $OUTPUT_AUTOFLUSH = 1;
      $self->_pipe_write($pipe_write);
      $self->online_logging_enabled(1);
   }
   else {
      # child
      my @log_entries;
      my $n_errors = 0;
      my $oktorun  = 1;
      QUEUE:
      while ($oktorun) {
         my $lines = read_stdin($read_timeout);
         last QUEUE unless $lines;
         LINE:
         while ( defined(my $line = shift @$lines) ) {
            # $line = ts,level,n_lines,message
            my ($ts, $level, $n_lines, $msg) = $line =~ m/^([^,]+),([^,]+),([^,]+),(.+)/s;
            if ( !$ts || !$level || !$n_lines || !$msg ) {
               warn "$line\n";
               next LINE;
            }
            if ( $n_lines > 1 ) {
               $n_lines--;  # first line
               for ( 1..$n_lines ) {
                  $msg .= shift @$lines;
               }
            }

            push @log_entries, Percona::WebAPI::Resource::LogEntry->new(
               pid       => $self->pid,
               entry_ts  => $ts,
               log_level => $level,
               message   => $msg,
               ($self->service ? (service => $self->service) : ()),
               ($self->data_ts ? (data_ts => $self->data_ts) : ()),
            );
         }  # LINE

         if ( scalar @log_entries ) { 
            eval {
               $client->post(
                  link      => $log_link,
                  resources => \@log_entries,
               );
            };
            if ( my $e = $EVAL_ERROR ) {
               # Safegaurd: don't spam the agent log file with errors.
               if ( ++$n_errors <= 10 ) {
                  warn "Error sending log entry to API: $e";
                  if ( $n_errors == 10 ) {
                     my $ts = ts(time, 1);  # 1=UTC
                     warn "$ts WARNING $n_errors consecutive errors, no more "
                        . "error messages will be printed until log entries "
                        . "are sent successfully again.\n";
                  }
               }
            }
            else {
               @log_entries = ();
               $n_errors    = 0;
            }
         }  # have log entries

         # Safeguard: don't use too much memory if we lose connection
         # to the API for a long time.
         my $n_log_entries = scalar @log_entries;
         if ( $n_log_entries > 1_000 ) {
            warn "$n_log_entries log entries in send buffer, "
               . "removing first 100 to avoid excessive usage.\n";
            @log_entries = @log_entries[100..($n_log_entries-1)];
         }
      }  # QUEUE

      if ( scalar @log_entries ) {
         my $ts = ts(time, 1);  # 1=UTC
         warn "$ts WARNING Failed to send these log entries "
            . "(timestamps are UTC):\n";
         foreach my $log ( @log_entries ) {
            warn sprintf("%s %s %s\n",
               $log->entry_ts,
               level_name($log->log_level),
               $log->message,
            );
         }
      }

      exit 0;
   } # child

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
   return if $self->online_logging;
   return $self->_log(0, 'DEBUG', @_);
}

sub info {
   my $self = shift;
   return $self->_log(1, 'INFO', @_);
}

sub warning {
   my $self = shift;
   $self->_set_exit_status();
   return $self->_log(1, 'WARNING', @_);
}

sub error {
   my $self = shift;
   $self->_set_exit_status();
   return $self->_log(1, 'ERROR', @_);
}

sub fatal {
   my $self = shift;
   $self->_set_exit_status();
   $self->_log(1, 'FATAL', @_);
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
   my ($self, $online, $level, $msg) = @_;

   my $ts = ts(time, 1);  # 1=UTC
   my $level_number = level_number($level);

   return if $self->quiet && $level_number < $self->quiet;

   chomp($msg);
   my $n_lines = 1;
   $n_lines++ while $msg =~ m/\n/g;

   if ( $online && $self->online_logging_enabled ) {
      while ( defined(my $log_entry = shift @{$self->_buffer}) ) {
         $self->_queue_log_entry(@$log_entry);
      }
      $self->_queue_log_entry($ts, $level_number, $n_lines, $msg);
   }
   else {
      if ( $online && $self->online_logging ) {
         push @{$self->_buffer}, [$ts, $level_number, $n_lines, $msg];
      }

      if ( $level_number >= 3 ) {  # warning
         print STDERR "$ts $level $msg\n";
      }
      else {
         print STDOUT "$ts $level $msg\n";
      }
   }

   return;
}

sub _queue_log_entry {
   my ($self, $ts, $log_level, $n_lines, $msg) = @_;
   print "$ts,$log_level,$n_lines,$msg\n";
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
