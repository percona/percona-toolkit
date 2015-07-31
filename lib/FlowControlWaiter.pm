# This program is copyright 2015 Percona LLC.
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
# FlowControlWaiter package
# ###########################################################################
{
# Package: FlowControlWaiter
# FlowControlWaiter helps limit load when there's too much Flow Control pausing 
# It is based on the other "Waiter" modules: 
# ReplicaLagWaiter & MySQLStatusWaiter
package FlowControlWaiter;

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
#   node    - Node dbh on which to check for wsrep_flow_control_paused_ns 
#   sleep   - Callback to sleep between checks.
#   max_pct - Max percent of flow control caused pause time to tolerate 
#
# Returns:
#   FlowControlWaiter object 
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(oktorun node sleep max_flow_ctl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $self = {
      %args
   };
   
   # Get current hi-res epoch seconds
   $self->{last_time} = time();   
   
   # Get nanoseconds server has been paused due to Flow Control
   my (undef, $last_fc_ns) = $self->{node}->selectrow_array('SHOW STATUS LIKE "wsrep_flow_control_paused_ns"');

   # Convert to seconds (float)
   $self->{last_fc_secs} = $last_fc_ns/1000_000_000;

   return bless $self, $class;
}

# Sub: wait
#   Wait for average flow control paused time fall below --max-flow-ctl
#
# Optional Arguments:
#   Progress - <Progress> object to report waiting
#
# Returns:
#   1 if average falls below max before timeout, else 0 if continue=yes, else die.
sub wait {
   my ( $self, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $pr = $args{Progress};

   my $oktorun       = $self->{oktorun};
   my $sleep         = $self->{sleep};
   my $node          = $self->{node};
   my $max_avg       = $self->{max_flow_ctl}/100;

   my $too_much_fc = 1;

   my $pr_callback;
   if ( $pr ) {
      # If you use the default Progress report callback, you'll need to
      # to add Transformers.pm to this tool.
      $pr_callback = sub {
         print STDERR "Pausing because PXC Flow Control is active\n";
         return;
      };
      $pr->set_callback($pr_callback);
   }

   # Loop where we wait for average pausing time caused by FC to fall below --max-flow-ctl  
   # Average pause time is calculated starting from the last iteration.
   while ( $oktorun->() && $too_much_fc ) {
      my $current_time = time();
      my (undef, $current_fc_ns) = $node->selectrow_array('SHOW STATUS LIKE "wsrep_flow_control_paused_ns"');
      my $current_fc_secs = $current_fc_ns/1000_000_000;
      my $current_avg = ($current_fc_secs - $self->{last_fc_secs}) / ($current_time - $self->{last_time});  
      if ( $current_avg > $max_avg ) { 
         if ( $pr ) {
            # There's no real progress because we can't estimate how long
            # it will take the values to abate.
            $pr->update(sub { return 0; });
         } 
         PTDEBUG && _d('Calling sleep callback');
         if ( $self->{simple_progress} ) {
            print STDERR "Waiting for Flow Control to abate\n";
         }
         $sleep->();
      } else {
         $too_much_fc = 0;
      }
      $self->{last_time} = $current_time;
      $self->{last_fc_secs} = $current_fc_secs;


   }

   PTDEBUG && _d('Flow Control is Ok');
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
# End FlowControlWaiter package
# ###########################################################################
