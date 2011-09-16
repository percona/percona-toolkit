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
# and adjustment (-1=down/decrease, 0=none, 1=up/increase) based on
# a moving average of how long operations are taking on the master.
# Regardless of that, slaves may still lag, so <wait()> waits for them
# to catchup based on the spec passed to <new()>.
package ReplicaLagLimiter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(spec slaves get_lag);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($spec) = @args{@required_args};

   my %specs = map {
      my ($key, $val) = split '=', $_;
      MKDEBUG && _d($key, '=', $val);
      lc($key) => $val;
   } @$spec;

   my $self = {
      target_time => 1,    # optimal time for master ops
      sample_size => 5,    # number of master ops to use for moving average
      max         => 1,    # max slave lag
      timeout     => 3600, # max time to wait for all slaves to catchup
      check       => 1,    # sleep time between checking slave lag
      continue    => 'no', # return true even if timeout
      %specs,              # slave wait specs from caller
      samples     => [],   # master op times
      moving_avg  => 0,    # moving avgerge of samples
      get_lag     => $args{get_lag},
   };

   return bless $self, $class;
}

sub validate_spec {
   # Permit calling as ReplicaLagLimiter-> or ReplicaLagLimiter::
   shift @_ if $_[0] eq 'ReplicaLagLimiter';
   my ( $spec ) = @_;
   if ( @$spec == 0 ) {
      die "spec array requires at least a max value\n";
   }
   my $have_max;
   foreach my $op ( @$spec ) {
      my ($key, $val) = split '=', $op;
      if ( !$key ) {
         die "invalid spec format, should be key=value: $spec\n";
      }
      if ( $key !~ m/(?:max|timeout|continue)/i )  {
         die "invalid spec: $spec\n";
      }
      if ( !$val ) {
         die "spec has no value: $spec\n";
      }
      if ( $key ne 'continue' && $val !~ m/^\d+$/ ) {
         die "value must be an integer: $spec\n";
      }
      if ( $key eq 'continue' && $val !~ m/(?:yes|no)/i ) {
         die "value for $key must be \"yes\" or \"no\"\n";
      }
      $have_max = 1 if $key eq 'max';
   }
   if ( !$have_max ) {
      die "max must be specified"
   }
}

sub update {
   my ($self, $t) = @_;
   MKDEBUG && _d('Sample time:', $t);
   my $sample_size = $self->{sample_size};
   my $samples     = $self->{samples};

   my $adjust = 0;
   if ( @$samples == $sample_size ) {
      shift @$samples;
      push @$samples, $t;
      my $sum = 0;
      map { $sum += $_ } @$samples;
      $self->{moving_avg} = $sum / $sample_size;
   
      MKDEBUG && _d('Moving average:', $self->{moving_avg});
      $adjust = $self->{target_time} <=> $self->{moving_avg};
   }
   else {
      MKDEBUG && _d('Saving sample', @$samples + 1, 'of', $sample_size);
      push @$samples, $t;
   }

   return $adjust;
}

# Sub: wait_for_slave
#   Wait for Seconds_Behind_Master on all slaves to become < max.
#
# Optional Arguments:
#   Progress - <Progress> object.
#
# Returns:
#   True if all slaves caught up, else 0 (timeout)
sub wait {
   my ( $self, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $pr       = $args{Progres};
   my $get_lag  = $self->{get_lag};
   my $slaves   = $self->{slaves};
   my $n_slaves = @$slaves;

   my $pr_callback;
   if ( $pr ) {
      # If you use the default Progress report callback, you'll need to
      # to add Transformers.pm to this tool.
      my $reported = 0;
      $pr_callback = sub {
         my ($fraction, $elapsed, $remaining, $eta, $slave_no) = @_;
         if ( !$reported ) {
            print STDERR "Waiting for replica "
               . ($slaves->[$slave_no]->{dsn}->{n} || '')
               . " to catchup...\n";
            $reported = 1;
         }
         else {
            print STDERR "Still waiting ($elapsed seconds)...\n";
         }
         return;
      };
      $pr->set_callback($pr_callback);
   }

   my ($max, $check, $timeout) = @{$self}{qw(max check timeout)};
   my $slave_no   = 0;
   my $slave      = $slaves->[$slave_no];
   my $t_start    = time;
   while ($slave && time - $t_start < $timeout) {
      MKDEBUG && _d('Checking slave lag on', $slave->{n});
      my $lag = $get_lag->($slave->{dbh});
      if ( !defined $lag || $lag > $max ) {
         MKDEBUG && _d('Replica lag', $lag, '>', $max, '; sleeping', $check);
         $pr->update(sub { return $slave_no; }) if $pr;
         sleep $check;
      }
      else {
         MKDEBUG && _d('Replica ready, lag', $lag, '<=', $max);
         $slave = $slaves->[++$slave_no];
      }
   }
   if ( $slave_no >= @$slave ) {
      MKDEBUG && _d('Timeout waiting for', $slaves->[$slave_no]->{dsn}->{n});
      return 0 unless $self->{continue};
   }
   MKDEBUG && _d('All slaves caught up');
   return 1;
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
