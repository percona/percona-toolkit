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
# ReplicaLagLimiter package
# ###########################################################################
{
# Package: ReplicaLagLimiter
# ReplicaLagLimiter helps limit slave lag when working on the master.
# There are two sides to this problem: operations on the master and
# slave lag.  Master ops that replicate can affect slave lag, so they
# should be adjusted to prevent overloading slaves.  <update()> returns
# an adjusted "n" value (number of whatever the master is doing) based
# on a weighted decaying average of "t", how long operations are taking.
# The desired master op time range is specified by target_t.
#
# Regardless of all that, slaves may still lag, so <wait()> waits for them
# to catch up based on the spec passed to <new()>.
package ReplicaLagLimiter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Time::HiRes qw(sleep time);
use Data::Dumper;

# Sub: new
#
# Required Arguments:
#   oktorun    - Callback that returns true if it's ok to continue running
#   get_lag    - Callback passed slave dbh and returns slave's lag
#   sleep      - Callback to sleep between checking lag.
#   max_lag    - Max lag
#   slaves     - Arrayref of slave cxn, like [{dsn=>{...}, dbh=>...},...]
#   initial_n  - Initial n value for <update()>
#   initial_t  - Initial t value for <update()>
#   target_t   - Target time for t in <update()>
#
# Optional Arguments:
#   weight - Weight of previous n/t values (default 0.75).
#
# Returns:
#   ReplicaLagLimiter object 
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(oktorun get_lag sleep max_lag slaves initial_n initial_t target_t);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $self = {
      %args,
      avg_n  => $args{initial_n},
      avg_t  => $args{initial_t},
      weight => $args{weight} || 0.75,
   };

   return bless $self, $class;
}

# Sub: update
#   Update weighted decaying average of master operation time.  Param n is
#   generic; it's how many of whatever the caller is doing (rows, checksums,
#   etc.).  Param s is how long this n took, in seconds (hi-res or not).
#
# Parameters:
#   n - Number of operations (rows, etc.)
#   t - Amount of time in seconds that n took
#
# Returns:
#   n adjust to meet target_t based on weighted decaying avg rate
sub update {
   my ($self, $n, $t) = @_;
   MKDEBUG && _d('Master op time:', $n, 'n /', $t, 's');

   $self->{avg_n}    = ($self->{avg_n} * $self->{weight}) + $n;
   $self->{avg_t}    = ($self->{avg_t} * $self->{weight}) + $t;
   $self->{avg_rate} = $self->{avg_n}  / $self->{avg_t};
   MKDEBUG && _d('Weighted avg rate:', $self->{avg_rate}, 'n/s');

   my $new_n = int($self->{avg_rate} * $self->{target_t});
   MKDEBUG && _d('Adjust n to', $new_n);
   return $new_n;
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
   if ( $pr ) {
      # If you use the default Progress report callback, you'll need to
      # to add Transformers.pm to this tool.
      $pr_callback = sub {
         my ($fraction, $elapsed, $remaining, $eta, $completed) = @_;
         if ( defined $worst->{lag} ) {
            print STDERR "Replica lag is $worst->{lag} seconds on "
               . "$worst->{dsn}->{n}.  Waiting.\n";
         }
         else {
            print STDERR "Replica $worst->{dsn}->{n} is stopped.  Waiting.\n";
         }
         return;
      };
      $pr->set_callback($pr_callback);
   }

   my @lagged_slaves = @$slaves;  # first check all slaves
   while ( $oktorun->() && @lagged_slaves ) {
      MKDEBUG && _d('Checking slave lag');
      for my $i ( 0..$#lagged_slaves ) {
         my $slave = $lagged_slaves[$i];
         my $lag   = $get_lag->($slave->{dbh});
         MKDEBUG && _d($slave->{dsn}->{n}, 'slave lag:', $lag);
         if ( !defined $lag || $lag > $max_lag ) {
            $slave->{lag} = $lag;
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
              defined $a && defined $b ? $a <=> $b
            : defined $a               ? -1
            :                             1;
         } @lagged_slaves;
         $worst = $lagged_slaves[0];
         MKDEBUG && _d(scalar @lagged_slaves, 'slaves are lagging, worst:',
            Dumper($worst));

         if ( $pr ) {
            # There's no real progress because we can't estimate how long
            # it will take all slaves to catch up.  The progress reports
            # are just to inform the user every 30s which slave is still
            # lagging this most.
            $pr->update(sub { return 0; });
         }

         MKDEBUG && _d('Calling sleep callback');
         $sleep->();
      }
   }

   MKDEBUG && _d('All slaves caught up');
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
# End ReplicaLagLimiter package
# ###########################################################################
