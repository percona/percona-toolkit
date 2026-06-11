# This program is copyright 2011-2026 Percona LLC and/or its affiliates.
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
# ReplicaLagWaiter package
# ###########################################################################
{
# Package: ReplicaLagWaiter
# ReplicaLagWaiter helps limit replica lag when working on the source.
package ReplicaLagWaiter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Time::HiRes qw(sleep time);
use Data::Dumper;

# Sub: new
#
# Required Arguments:
#   oktorun - Callback that returns true if it's ok to continue running
#   get_lag - Callback passed replica dbh and returns replica's lag
#   sleep   - Callback to sleep between checking lag.
#   max_lag - Max lag
#   replicas  - Arrayref of <Cxn> objects
#
# Returns:
#   ReplicaLagWaiter object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(oktorun get_lag sleep max_lag replicas);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $self = {
      %args,
   };

   return bless $self, $class;
}

# Sub: wait
#   Wait for Seconds_Behind_Source on all replicas to become < max.
#
# Optional Arguments:
#   Progress - <Progress> object to report waiting
#
# Returns:
#   1 if all replicas catch up before timeout, else 0 if continue=yes, else die.
sub wait {
   my ( $self, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $pr = $args{Progress};

   my $oktorun  = $self->{oktorun};
   my $get_lag  = $self->{get_lag};
   my $sleep    = $self->{sleep};
   my $replicas = $self->{replicas}; 
   my $max_lag  = $self->{max_lag};

   my $worst;  # most lagging replica
   my $pr_callback;
   my $pr_first_report;

   ### refresh list of replicas. In: self passed to wait()
   ### Returns: new replica list
   my $pr_refresh_replica_list = sub {
      my ($self) = @_;
      my ($replicas, $refresher) = ($self->{replicas}, $self->{get_replicas_cb});
      return $replicas if ( not defined $refresher );
      my $before = join ' ', sort map {$_->description()} @$replicas;
      $replicas = $refresher->();
      my $after = join ' ', sort map {$_->description()} @$replicas;
      if ($before ne $after) {
         $self->{replicas} = $replicas;
         printf STDERR "Replica set to watch has changed\n  Was: %s\n  Now: %s\n",
            $before, $after;
      }
      return($self->{replicas});
   };

   $replicas = $pr_refresh_replica_list->($self);

   if ( $pr ) {
      # If you use the default Progress report callback, you'll need to
      # to add Transformers.pm to this tool.
      $pr_callback = sub {
         my ($fraction, $elapsed, $remaining, $eta, $completed) = @_;
         my $dsn_name = $worst->{cxn}->name();
         my $dsn_description = $worst->{cxn}->description();
         if ( defined $worst->{lag} ) {
            print STDERR "Replica lag is " . ($worst->{lag} || '?')
               . " seconds on $dsn_description.  Waiting.\n";
         }
         else {
            if ($self->{fail_on_stopped_replication}) {
                die 'replication is stopped';
            }
            print STDERR "Replica $dsn_name is stopped.  Waiting.\n";
         }
         return;
      };
      $pr->set_callback($pr_callback);

      # If a replic is stopped, don't wait 30s (or whatever interval)
      # to report this.  Instead, report it once, immediately, then
      # keep reporting it every interval.
      $pr_first_report = sub {
         my $dsn_name = $worst->{cxn}->name();
         if ( !defined $worst->{lag} ) {
            if ($self->{fail_on_stopped_replication}) {
                die 'replication is stopped';
            }
            print STDERR "Replica $dsn_name is stopped.  Waiting.\n";
         }
         return;
      };
   }

   # First check all replicas.
   my @lagged_replicas = map { {cxn=>$_, lag=>undef} } @$replicas;
   while ( $oktorun->() && @lagged_replicas ) {
      PTDEBUG && _d('Checking replica lag');

      ### while we were waiting our list of replicas may have changed
      $replicas = $pr_refresh_replica_list->($self);
      my $watched = 0;
      @lagged_replicas = grep {
         my $replica_name = $_->{cxn}->name();
         grep {$replica_name eq $_->name()} @{$replicas // []}
                            } @lagged_replicas;

      for my $i ( 0..$#lagged_replicas ) {
         my $lag;
         eval {
             $lag = $get_lag->($lagged_replicas[$i]->{cxn});
         };
         if ($EVAL_ERROR) {
             die $EVAL_ERROR;
         }
         PTDEBUG && _d($lagged_replicas[$i]->{cxn}->name(),
            'replica lag:', $lag);
         if ( !defined $lag || $lag > $max_lag ) {
            $lagged_replicas[$i]->{lag} = $lag;
         }
         else {
            delete $lagged_replicas[$i];
         }
      }

      # Remove replicas that aren't lagging.
      @lagged_replicas = grep { defined $_ } @lagged_replicas;
      if ( @lagged_replicas ) {
         # Sort lag, undef is highest because it means the replica is stopped.
         @lagged_replicas = reverse sort {
              defined $a->{lag} && defined $b->{lag} ? $a->{lag} <=> $b->{lag}
            : defined $a->{lag}                      ? -1
            :                                           1;
         } @lagged_replicas;
         $worst = $lagged_replicas[0];
         PTDEBUG && _d(scalar @lagged_replicas, 'replicas are lagging, worst:',
            $worst->{lag}, 'on', Dumper($worst->{cxn}->dsn()));

         if ( $pr ) {
            # There's no real progress because we can't estimate how long
            # it will take all replicas to catch up.  The progress reports
            # are just to inform the user every 30s which replica is still
            # lagging this most.
            $pr->update(
               sub { return 0; },
               first_report => $pr_first_report,
            );
         }

         PTDEBUG && _d('Calling sleep callback');
         $sleep->($worst->{cxn}, $worst->{lag});
      }
   }

   PTDEBUG && _d('All replicas caught up');
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
# End ReplicaLagWaiter package
# ###########################################################################
