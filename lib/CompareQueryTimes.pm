# This program is copyright 2009-2011 Percona Ireland Ltd.
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
# CompareQueryTimes package
# ###########################################################################
{
# Package: CompareQueryTimes
# CompareQueryTimes compares query execution times.
package CompareQueryTimes;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

Transformers->import(qw(micro_t));
use POSIX qw(floor);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Significant percentage increase for each bucket.  For example,
# 1us to 4us is a 300% increase, but in reality that is not significant.
# But a 500% increase to 6us may be significant.  In the 1s+ range (last
# bucket), since the time is already so bad, even a 20% increase (e.g. 1s
# to 1.2s) is significant.
my @bucket_threshold = qw(500 100  100   500 50   50    20 1   );
# my @bucket_labels  = qw(1us 10us 100us 1ms 10ms 100ms 1s 10s+);

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   get_id - Callback used by report() to transform query to its ID
#
# Returns:
#   CompareQueryTimes object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(get_id);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      diffs   => {},
      samples => {},
   };
   return bless $self, $class;
}

sub before_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   return $args{event};
}

# Sub: execute
#   Execute query if not already executed.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   event - Hashref with event attributes and values
#   dbh   - dbh on which to execute the event
#
# Returns:
#   Hashref of event with Query_time attribute added
sub execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};

   if ( exists $event->{Query_time} ) {
      PTDEBUG && _d('Query already executed');
      return $event;
   }

   PTDEBUG && _d('Executing query');
   my $query = $event->{arg};
   my ( $start, $end, $query_time );

   $event->{Query_time} = 0;
   eval {
      $start = time();
      $dbh->do($query);
      $end   = time();
      $query_time = sprintf '%.6f', $end - $start;
   };
   die "Failed to execute query: $EVAL_ERROR" if $EVAL_ERROR;

   $event->{Query_time} = $query_time;

   return $event;
}

sub after_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   return $args{event};
}

# Sub: compare
#   Compare executed events.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   events - Arrayref of event hashrefs
#
# Returns:
#   Hash of differences
sub compare {
   my ( $self, %args ) = @_;
   my @required_args = qw(events);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($events) = @args{@required_args};

   my $different_query_times = 0;

   my $event0   = $events->[0];
   my $item     = $event0->{fingerprint} || $event0->{arg};
   my $sampleno = $event0->{sampleno}    || 0;
   my $t0       = $event0->{Query_time}  || 0;
   my $b0       = bucket_for($t0);

   my $n_events = scalar @$events;
   foreach my $i ( 1..($n_events-1) ) {
      my $event = $events->[$i];
      my $t     = $event->{Query_time};
      my $b     = bucket_for($t);

      if ( $b0 != $b ) {
         # Save differences.
         my $diff = abs($t0 - $t);
         $different_query_times++;
         $self->{diffs}->{big}->{$item}->{$sampleno}
            = [ micro_t($t0), micro_t($t), micro_t($diff) ];
         $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
      }
      else {
         my $inc = percentage_increase($t0, $t);
         if ( $inc >= $bucket_threshold[$b0] ) {
            # Save differences.
            $different_query_times++;
            $self->{diffs}->{in_bucket}->{$item}->{$sampleno}
               = [ micro_t($t0), micro_t($t), $inc, $bucket_threshold[$b0] ];
            $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
         }
      }
   }

   return (
      different_query_times => $different_query_times,
   );
}

# Sub: buck_for
#   Calculate bucket for value.
#
# Parameters:
#   $val - Value
#
# Returns:
#   Bucket number for value
sub bucket_for {
   my ( $val ) = @_;
   die "I need a val" unless defined $val;
   return 0 if $val == 0;
   my $bucket = floor(log($val) / log(10)) + 6;
   $bucket = $bucket > 7 ? 7 : $bucket < 0 ? 0 : $bucket;
   return $bucket;
}

# Sub: percentage_increase
#   Calculate percentage increase between two values.
#
# Parameters:
#   $x - First value
#   $y - Second value
#
# Returns:
#   Percentage increase from first to second value
sub percentage_increase {
   my ( $x, $y ) = @_;
   return 0 if $x == $y;

   if ( $x > $y ) {
      my $z = $y;
         $y = $x;
         $x = $z;
   }

   if ( $x == 0 ) {
      return 1000;  # This should trigger all buckets' thresholds.
   }

   return sprintf '%.2f', (($y - $x) / $x) * 100;
}


# Sub: report
#   Report differences found.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   hosts - Arrayref of hosts
#
# Returns:
#   Report text of differences
sub report {
   my ( $self, %args ) = @_;
   my @required_args = qw(hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($hosts) = @args{@required_args};

   return unless keys %{$self->{diffs}};

   # These columns are common to all the reports; make them just once.
   my $query_id_col = {
      name        => 'Query ID',
   };
   my $hostno = 0;
   my @host_cols = map {
      $hostno++;
      my $col = { name => "host$hostno" };
      $col;
   } @$hosts;

   my @reports;
   foreach my $diff ( qw(big in_bucket) ) {
      my $report = "_report_diff_$diff";
      push @reports, $self->$report(
         query_id_col => $query_id_col,
         host_cols    => \@host_cols,
         %args
      );
   }

   return join("\n", @reports);
}

# Sub: _report_diff_big
#   Report big differences in query times.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   query_id_col - Hashref <ReportFormat> column descriptor
#   hosts        - Arrayref of hosts
#
# Returns:
#   Big query time diff report
sub _report_diff_big {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{big}};

   my $report = new ReportFormatter();
   $report->title('Big query time differences');
   my $hostno = 0;
   $report->set_columns(
      $args{query_id_col},
      (map {
         $hostno++;
         my $col = { name => "host$hostno", right_justify => 1  };
         $col;
      } @{$args{hosts}}),
      { name => 'Difference', right_justify => 1 },
   );

   my $diff_big = $self->{diffs}->{big};
   foreach my $item ( sort keys %$diff_big ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_big->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_big->{$item}};
   }

   return $report->get_report();
}

# Sub: _report_diff_big
#   Report smaller, "in bucket" query time differences.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   query_id_col - Hashref <ReportFormat> column descriptor
#   hosts        - Arrayref of hosts
#
# Returns:
#   In bucket query time diff report
sub _report_diff_in_bucket {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{in_bucket}};

   my $report = new ReportFormatter();
   $report->title('Significant query time differences');
   my $hostno = 0;
   $report->set_columns(
      $args{query_id_col},
      (map {
         $hostno++;
         my $col = { name => "host$hostno", right_justify => 1  };
         $col;
      } @{$args{hosts}}),
      { name => '%Increase',  right_justify => 1 },
      { name => '%Threshold', right_justify => 1 },
   );

   my $diff_in_bucket = $self->{diffs}->{in_bucket};
   foreach my $item ( sort keys %$diff_in_bucket ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_in_bucket->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_in_bucket->{$item}};
   }

   return $report->get_report();
}

# Sub: samples
#   Return samples of queries with differences.
#
# Parameters:
#   $item - Query fingerprint
#
# Returns:
#   Array of queries
sub samples {
   my ( $self, $item ) = @_;
   return unless $item;
   my @samples;
   foreach my $sampleno ( keys %{$self->{samples}->{$item}} ) {
      push @samples, $sampleno, $self->{samples}->{$item}->{$sampleno};
   }
   return @samples;
}


# Sub: reset
#   Reset internal state for another run.
sub reset {
   my ( $self ) = @_;
   $self->{diffs}   = {};
   $self->{samples} = {};
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
# End CompareQueryTimes package
# ###########################################################################
