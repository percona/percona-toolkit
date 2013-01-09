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
# ReplicaLagWaiter package
# ###########################################################################
{
# Package: ReplicaLagWaiter
# ReplicaLagWaiter helps limit slave lag when working on the master.
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
#   get_lag - Callback passed slave dbh and returns slave's lag
#   sleep   - Callback to sleep between checking lag.
#   max_lag - Max lag
#   slaves  - Arrayref of <Cxn> objects
#
# Returns:
#   ReplicaLagWaiter object 
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(oktorun get_lag sleep max_lag slaves);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $self = {
      %args,
   };

   return bless $self, $class;
}

# Sub: wait
#   Wait for Seconds_Behind_Master on all slaves to become < max.
#
# Optional Arguments:
#   Progress - <Progress> object to report waiting
#
# Returns:
#   1 if all slaves catch up before timeout, else 0 if continue=yes, else die.
sub wait {
   my ( $self, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $pr = $args{Progress};

   my $oktorun = $self->{oktorun};
   my $get_lag = $self->{get_lag};
   my $sleep   = $self->{sleep};
   my $slaves  = $self->{slaves};
   my $max_lag = $self->{max_lag};

   my $worst;  # most lagging slave
   my $pr_callback;
   my $pr_first_report;
   if ( $pr ) {
      # If you use the default Progress report callback, you'll need to
      # to add Transformers.pm to this tool.
      $pr_callback = sub {
         my ($fraction, $elapsed, $remaining, $eta, $completed) = @_;
         my $dsn_name = $worst->{cxn}->name();
         if ( defined $worst->{lag} ) {
            print STDERR "Replica lag is " . ($worst->{lag} || '?')
               . " seconds on $dsn_name.  Waiting.\n";
         }
         else {
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
            print STDERR "Replica $dsn_name is stopped.  Waiting.\n";
         }
         return;
      };
   }

   # First check all slaves.
   my @lagged_slaves = map { {cxn=>$_, lag=>undef} } @$slaves;  
   while ( $oktorun->() && @lagged_slaves ) {
      PTDEBUG && _d('Checking slave lag');
      for my $i ( 0..$#lagged_slaves ) {
         my $lag = $get_lag->($lagged_slaves[$i]->{cxn});
         PTDEBUG && _d($lagged_slaves[$i]->{cxn}->name(),
            'slave lag:', $lag);
         if ( !defined $lag || $lag > $max_lag ) {
            $lagged_slaves[$i]->{lag} = $lag;
         }
         else {
            delete $lagged_slaves[$i];
         }
      }

      # Remove slaves that aren't lagging.
      @lagged_slaves = grep { defined $_ } @lagged_slaves;
      if ( @lagged_slaves ) {
         # Sort lag, undef is highest because it means the slave is stopped.
         @lagged_slaves = reverse sort {
              defined $a->{lag} && defined $b->{lag} ? $a->{lag} <=> $b->{lag}
            : defined $a->{lag}                      ? -1
            :                                           1;
         } @lagged_slaves;
         $worst = $lagged_slaves[0];
         PTDEBUG && _d(scalar @lagged_slaves, 'slaves are lagging, worst:',
            $worst->{lag}, 'on', Dumper($worst->{cxn}->dsn()));

         if ( $pr ) {
            # There's no real progress because we can't estimate how long
            # it will take all slaves to catch up.  The progress reports
            # are just to inform the user every 30s which slave is still
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

   PTDEBUG && _d('All slaves caught up');
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
