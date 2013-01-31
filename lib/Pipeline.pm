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
# Pipeline package
# ###########################################################################
{
# Package: Pipeline
# Pipeline executes and controls a list of pipeline processes.
package Pipeline;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;
use Time::HiRes qw(time);

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $self = {
      # default values for optional args
      instrument        => PTDEBUG,
      continue_on_error => 0,

      # specified arg values override defaults
      %args,

      # private/internal vars
      procs           => [],  # coderefs for pipeline processes
      names           => [],  # names for each ^ pipeline proc
      instrumentation => {    # keyed on proc index in procs
         Pipeline => {
            time  => 0,
            calls => 0,
         },
      },
   };
   return bless $self, $class;
}

sub add {
   my ( $self, %args ) = @_;
   my @required_args = qw(process name);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($process, $name) = @args{@required_args};

   push @{$self->{procs}}, $process;
   push @{$self->{names}}, $name;
   $self->{retries}->{$name} = $args{retry_on_error} || 100;
   if ( $self->{instrument} ) {
      $self->{instrumentation}->{$name} = { time => 0, calls => 0 };
   }
   PTDEBUG && _d("Added pipeline process", $name);

   return;
}

sub processes {
   my ( $self ) = @_;
   return @{$self->{names}};
}

# Sub: execute
#   Execute all pipeline processes until not oktorun.  The oktorun arg
#   must be a reference.  The pipeline will run until oktorun is false.
#   The oktorun ref is passed to every pipeline proc so they can completely
#   terminate pipeline execution.  A proc signals that it wants to restart
#   execution of the pipeline from the first proc by returning undef.
#   If a proc both sets oktorun to false and returns undef, this sub will
#   return with some info about where the pipeline stopped.
#
# Parameters:
#   %args    - Arguments passed to each pipeline process.
#
# Required Arguments:
#   oktorun - Scalar ref that indicates it's ok to run when true.
#
# Optional Arguments:
#   pipeline_data - Hashref passed through all processes.
#
# Returns:
#   Hashref with information about where and why the pipeline terminated.
sub execute {
   my ( $self, %args ) = @_;

   die "Cannot execute pipeline because no process have been added"
      unless scalar @{$self->{procs}};

   my $oktorun = $args{oktorun};
   die "I need an oktorun argument" unless $oktorun;
   die '$oktorun argument must be a reference' unless ref $oktorun;

   my $pipeline_data = $args{pipeline_data} || {};
   $pipeline_data->{oktorun} = $oktorun;

   my $stats = $args{stats};  # optional

   PTDEBUG && _d("Pipeline starting at", time);
   my $instrument = $self->{instrument};
   my $processes  = $self->{procs};
   EVENT:
   while ( $$oktorun ) {
      my $procno  = 0;  # so we can see which proc if one causes an error
      my $output;
      eval {
         PIPELINE_PROCESS:
         while ( $procno < scalar @{$self->{procs}} ) {
            my $call_start = $instrument ? time : 0;

            # Execute this pipeline process.
            PTDEBUG && _d("Pipeline process", $self->{names}->[$procno]);
            $output = $processes->[$procno]->($pipeline_data);

            if ( $instrument ) {
               my $call_end = time;
               my $call_t   = $call_end - $call_start;
               $self->{instrumentation}->{$self->{names}->[$procno]}->{time} += $call_t;
               $self->{instrumentation}->{$self->{names}->[$procno]}->{count}++;
               $self->{instrumentation}->{Pipeline}->{time} += $call_t;
               $self->{instrumentation}->{Pipeline}->{count}++;
            }
            if ( !$output ) {
               PTDEBUG && _d("Pipeline restarting early after",
                  $self->{names}->[$procno]);
               if ( $stats ) {
                  $stats->{"pipeline_restarted_after_"
                     .$self->{names}->[$procno]}++;
               }
               last PIPELINE_PROCESS;
            }
            $procno++;
         }
      };
      if ( $EVAL_ERROR ) {
         my $name = $self->{names}->[$procno] || "";
         my $msg  = "Pipeline process " . ($procno + 1)
                  . " ($name) caused an error: "
                  . $EVAL_ERROR;
         if ( !$self->{continue_on_error} ) {
            die $msg . "Terminating pipeline because --continue-on-error "
               . "is false.\n";
         }
         elsif ( defined $self->{retries}->{$name} ) {
            my $n = $self->{retries}->{$name};
            if ( $n ) {
               warn $msg . "Will retry pipeline process $procno ($name) "
                  . "$n more " . ($n > 1 ? "times" : "time") . ".\n";
               $self->{retries}->{$name}--;
            }
            else {
               die $msg . "Terminating pipeline because process $procno "
                  . "($name) caused too many errors.\n";
            }
         }
         else {
            warn $msg;
         }
      }
   }

   PTDEBUG && _d("Pipeline stopped at", time);
   return;
}

sub instrumentation {
   my ( $self ) = @_;
   return $self->{instrumentation};
}

sub reset {
   my ( $self ) = @_;
   foreach my $proc_name ( @{$self->{names}} ) {
      if ( exists $self->{instrumentation}->{$proc_name} ) {
         $self->{instrumentation}->{$proc_name}->{calls} = 0;
         $self->{instrumentation}->{$proc_name}->{time}  = 0;
      }
   }
   $self->{instrumentation}->{Pipeline}->{calls} = 0;
   $self->{instrumentation}->{Pipeline}->{time}  = 0;
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
# End Pipeline package
# ###########################################################################
