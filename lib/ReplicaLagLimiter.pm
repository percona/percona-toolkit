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

# Sub: new
#
# Required Arguments:
#   spec      - --replicat-lag spec (arrayref of option=value pairs)
#   slaves    - Arrayref of slave cxn, like [{dsn=>{...}, dbh=>...},...]
#   get_lag   - Callback passed slave dbh and returns slave's lag
#   initial_n - Initial n value for <update()>
#   initial_t - Initial t value for <update()>
#   target_t  - Target time for t in <update()>
#
# Optional Arguments:
#   weight - Weight of previous n/t values (default 0.75).
#
# Returns:
#   ReplicaLagLimiter object 
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(spec slaves get_lag initial_n initial_t target_t);
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
      max       => 1,     # max slave lag
      timeout   => 3600,  # max time to wait for all slaves to catch up
      check     => 1,     # sleep time between checking slave lag
      continue  => 'no',  # return true even if timeout
      %specs,             # slave wait specs from caller
      slaves    => $args{slaves},
      get_lag   => $args{get_lag},
      avg_n     => $args{initial_n},
      avg_t     => $args{initial_t},
      target_t  => $args{target_t},
      weight    => $args{weight} || 0.75,
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
      if ( !$key || !$val ) {
         die "invalid spec format, should be option=value: $op\n";
      }
      if ( $key !~ m/(?:max|timeout|continue)/i )  {
         die "unknown option in spec: $op\n";
      }
      if ( $key ne 'continue' && $val !~ m/^\d+$/ ) {
         die "value must be an integer: $op\n";
      }
      if ( $key eq 'continue' && $val !~ m/(?:yes|no)/i ) {
         die "value for $key must be \"yes\" or \"no\"\n";
      }
      $have_max = 1 if $key eq 'max';
   }
   if ( !$have_max ) {
      die "max must be specified"
   }
   return 1;
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

# Sub: wait_for_slave
#   Wait for Seconds_Behind_Master on all slaves to become < max.
#
# Optional Arguments:
#   Progress - <Progress> object to report waiting
#
# Returns:
#   True if all slaves catch up before timeout, else die unless continue is true
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
               . " to catch up...\n";
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
      MKDEBUG && _d('Checking slave lag on', $slave->{dsn}->{n});
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
   if ( $slave_no < @$slaves && $self->{continue} eq 'no' ) {
      die "Timeout waiting for replica " . $slaves->[$slave_no]->{dsn}->{n}
        . " to catch up\n";
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
