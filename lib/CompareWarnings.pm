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
# CompareWarnings package
# ###########################################################################
{
# Package: CompareWarnings
# CompareWarnings compares query warnings.
package CompareWarnings;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Required args:
#   * get_id  coderef: used by report() to trf query to its ID
#   * common modules
# Optional args:
#   * clear-warnings        bool: clear warnings before each run
#   * clear-warnings-table  scalar: table to select from to clear warnings
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(get_id Quoter QueryParser);
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

# Required args:
#   * event  hashref: an event
#   * dbh    scalar: active dbh
# Optional args:
#   * db             scalar: database name to create temp table in unless...
#   * temp-database  scalar: ...temp db name is given
# Returns: hashref
# Can die: yes
# before_execute() selects from its special temp table to clear the warnings
# if the module was created with the clear arg specified.  The temp table is
# created if there's a db or temp db and the table doesn't exist yet.
sub before_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};
   my $sql;

   return $event unless $self->{'clear-warnings'};

   if ( my $tbl = $self->{'clear-warnings-table'} ) {
      $sql = "SELECT * FROM $tbl LIMIT 1";
      PTDEBUG && _d($sql);
      eval {
         $dbh->do($sql);
      };
      die "Failed to SELECT from clear warnings table: $EVAL_ERROR"
         if $EVAL_ERROR;
   }
   else {
      my $q    = $self->{Quoter};
      my $qp   = $self->{QueryParser};
      my @tbls = $qp->get_tables($event->{arg});
      my $ok   = 0;
      TABLE:
      foreach my $tbl ( @tbls ) {
         $sql = "SELECT * FROM $tbl LIMIT 1";
         PTDEBUG && _d($sql);
         eval {
            $dbh->do($sql);
         };
         if ( $EVAL_ERROR ) {
            PTDEBUG && _d('Failed to clear warnings');
         }
         else {
            PTDEBUG && _d('Cleared warnings');
            $ok = 1;
            last TABLE;
         }
      }
      die "Failed to clear warnings"
         unless $ok;
   }

   return $event;
}

# Required args:
#   * event  hashref: an event
#   * dbh    scalar: active dbh
# Returns: hashref
# Can die: yes
# execute() executes the event's query if is hasn't already been executed. 
# Any prep work should have been done in before_execute().  Adds Query_time
# attrib to the event.
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

# Required args:
#   * event  hashref: an event
#   * dbh    scalar: active dbh
# Returns: hashref
# Can die: yes
# after_execute() gets any warnings from SHOW WARNINGS.
sub after_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};

   my $warnings;
   my $warning_count;
   eval {
      $warnings      = $dbh->selectall_hashref('SHOW WARNINGS', 'Code');
      $warning_count = $dbh->selectcol_arrayref('SELECT @@warning_count')->[0];
   };
   die "Failed to SHOW WARNINGS: $EVAL_ERROR"
      if $EVAL_ERROR;

   # We munge the warnings to be the same thing so testing is easier, otherwise
   # a ton of code has to be involved.  This seems to be the minimal necessary
   # code to handle changes in warning messages.
   map {
      $_->{Message} =~ s/Out of range value adjusted/Out of range value/;
   } values %$warnings;
   $event->{warning_count} = $warning_count || 0;
   $event->{warnings}      = $warnings;

   return $event;
}

# Required args:
#   * events  arrayref: events
# Returns: array
# Can die: yes
# compare() compares events that have been run through before_execute(),
# execute() and after_execute().  Only a "summary" of differences is
# returned.  Specific differences are saved internally and are reported
# by calling report() later.
sub compare {
   my ( $self, %args ) = @_;
   my @required_args = qw(events);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($events) = @args{@required_args};

   my $different_warning_counts = 0;
   my $different_warnings       = 0;
   my $different_warning_levels = 0;

   my $event0   = $events->[0];
   my $item     = $event0->{fingerprint} || $event0->{arg};
   my $sampleno = $event0->{sampleno} || 0;
   my $w0       = $event0->{warnings};

   my $n_events = scalar @$events;
   foreach my $i ( 1..($n_events-1) ) {
      my $event = $events->[$i];

      if ( ($event0->{warning_count} || 0) != ($event->{warning_count} || 0) ) {
         PTDEBUG && _d('Warning counts differ:',
            $event0->{warning_count}, $event->{warning_count});
         $different_warning_counts++;
         $self->{diffs}->{warning_counts}->{$item}->{$sampleno}
            = [ $event0->{warning_count} || 0, $event->{warning_count} || 0 ];
         $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
      }

      # Check the warnings on event0 against this event.
      my $w = $event->{warnings};

      # Neither event had warnings.
      next if !$w0 && !$w;

      my %new_warnings;
      foreach my $code ( keys %$w0 ) {
         if ( exists $w->{$code} ) {
            if ( $w->{$code}->{Level} ne $w0->{$code}->{Level} ) {
               PTDEBUG && _d('Warning levels differ:',
                  $w0->{$code}->{Level}, $w->{$code}->{Level});
               # Save differences.
               $different_warning_levels++;
               $self->{diffs}->{levels}->{$item}->{$sampleno}
                  = [ $code, $w0->{$code}->{Level}, $w->{$code}->{Level},
                      $w->{$code}->{Message} ];
               $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
            }
            delete $w->{$code};
         }
         else {
            # This warning code is on event0 but not on this event.
            PTDEBUG && _d('Warning gone:', $w0->{$code}->{Message});
            # Save differences.
            $different_warnings++;
            $self->{diffs}->{warnings}->{$item}->{$sampleno}
               = [ 0, $code, $w0->{$code}->{Message} ];
            $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
         }
      }

      # Any warning codes on this event not deleted above are new;
      # i.e. they weren't on event0.
      foreach my $code ( keys %$w ) {
         PTDEBUG && _d('Warning new:', $w->{$code}->{Message});
         # Save differences.
         $different_warnings++;
         $self->{diffs}->{warnings}->{$item}->{$sampleno}
            = [ $i, $code, $w->{$code}->{Message} ];
         $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
      }

      # EventAggregator won't know what do with this hashref so delete it.
      delete $event->{warnings};
   }
   delete $event0->{warnings};

   return (
      different_warning_counts => $different_warning_counts,
      different_warnings       => $different_warnings,
      different_warning_levels => $different_warning_levels,
   );
}

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
   foreach my $diff ( qw(warnings levels warning_counts) ) {
      my $report = "_report_diff_$diff";
      push @reports, $self->$report(
         query_id_col => $query_id_col,
         host_cols    => \@host_cols,
         %args
      );
   }

   return join("\n", @reports);
}

sub _report_diff_warnings {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{warnings}};

   my $report = new ReportFormatter(extend_right => 1);
   $report->title('New warnings');
   $report->set_columns(
      $args{query_id_col},
      { name => 'Host', },
      { name => 'Code', right_justify => 1 },
      { name => 'Message' },
   );

   my $diff_warnings = $self->{diffs}->{warnings};
   foreach my $item ( sort keys %$diff_warnings ) {
      map {
         my ($hostno, $code, $message) = @{$diff_warnings->{$item}->{$_}};
         $report->add_line(
            $get_id->($item) . '-' . $_,
            "host" . ($hostno + 1), $code, $message,
         );
      } sort { $a <=> $b } keys %{$diff_warnings->{$item}};
   }

   return $report->get_report();
}

sub _report_diff_levels {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{levels}};

   my $report = new ReportFormatter(extend_right => 1);
   $report->title('Warning level differences');
   my $hostno = 0;
   $report->set_columns(
      $args{query_id_col},
      { name => 'Code', right_justify => 1 },
      (map {
         $hostno++;
         my $col = { name => "host$hostno", right_justify => 1  };
         $col;
      } @{$args{hosts}}),
      { name => 'Message' },
   );

   my $diff_levels = $self->{diffs}->{levels};
   foreach my $item ( sort keys %$diff_levels ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_levels->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_levels->{$item}};
   }

   return $report->get_report();
}

sub _report_diff_warning_counts {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{warning_counts}};

   my $report = new ReportFormatter();
   $report->title('Warning count differences');
   my $hostno = 0;
   $report->set_columns(
      $args{query_id_col},
      (map {
         $hostno++;
         my $col = { name => "host$hostno", right_justify => 1  };
         $col;
      } @{$args{hosts}}),
   );

   my $diff_warning_counts = $self->{diffs}->{warning_counts};
   foreach my $item ( sort keys %$diff_warning_counts ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_warning_counts->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_warning_counts->{$item}};
   }

   return $report->get_report();
}

sub samples {
   my ( $self, $item ) = @_;
   return unless $item;
   my @samples;
   foreach my $sampleno ( keys %{$self->{samples}->{$item}} ) {
      push @samples, $sampleno, $self->{samples}->{$item}->{$sampleno};
   }
   return @samples;
}

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
# End CompareWarnings package
# ###########################################################################
