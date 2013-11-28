# This program is copyright 2008-2011 Percona Ireland Ltd.
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
# QueryReportFormatter package
# ###########################################################################
{
# Package: QueryReportFormatter
# QueryReportFormatter is used primarily by mk-query-digest to print reports.
# The main sub is print_reports() which prints the various reports for
# mk-query-digest --report-format.  Each report is produced in a sub of
# the same name; e.g. --report-format=query_report == sub query_report().
# The given ea (<EventAggregator> object) is expected to be "complete"; i.e.
# fully aggregated and $ea->calculate_statistical_metrics() already called.
# Subreports "profile" and "prepared" require the ReportFormatter module,
# which is also in mk-query-digest.
package QueryReportFormatter;

use Lmo;
use English qw(-no_match_vars);
use POSIX qw(floor);

Transformers->import(qw(
   shorten micro_t parse_timestamp unix_timestamp make_checksum percentage_of
   crc32
));

use constant PTDEBUG           => $ENV{PTDEBUG} || 0;
use constant LINE_LENGTH       => 74;
use constant MAX_STRING_LENGTH => 10;

{ local $EVAL_ERROR; eval { require Quoter } };
{ local $EVAL_ERROR; eval { require ReportFormatter } };

# Sub: new
# 
# Parameters:
#   %args - Required arguments
#
# Required Arguments:
#   OptionParser  - <OptionParser> object
#   QueryRewriter - <QueryRewriter> object
#   Quoter        - <Quoter> object
#
# Optional arguments:
#   QueryReview     - <QueryReview> object used in <query_report()>
#   dbh             - dbh used in <explain_report()>
#
# Returns:
#   QueryReportFormatter object
has Quoter => (
   is      => 'ro',
   isa     => 'Quoter',
   default => sub { Quoter->new() },
);

has label_width => (
   is      => 'ro',
   isa     => 'Int',
);

has global_headers => (
   is      => 'ro',
   isa     => 'ArrayRef',
   default => sub { [qw(    total min max avg 95% stddev median)] },
);

has event_headers => (
   is      => 'ro',
   isa     => 'ArrayRef',
   default => sub { [qw(pct total min max avg 95% stddev median)] },
);

has show_all => (
   is      => 'ro',
   isa     => 'HashRef',
   default => sub { {} },
);

has ReportFormatter => (
   is      => 'ro',
   isa     => 'ReportFormatter',
   builder => '_build_report_formatter',
);

sub _build_report_formatter {
   return ReportFormatter->new(
      line_width       => LINE_LENGTH,
      extend_right     => 1,
   );
}

sub BUILDARGS {
   my $class = shift;
   my $args  = $class->SUPER::BUILDARGS(@_);

   foreach my $arg ( qw(OptionParser QueryRewriter) ) {
      die "I need a $arg argument" unless $args->{$arg};
   }

   # If ever someone wishes for a wider label width.
   my $label_width = $args->{label_width} ||= 12;
   PTDEBUG && _d('Label width:', $label_width);

   my $o = delete $args->{OptionParser};
   my $self = {
      %$args,
      options        => {
         shorten          => 1024,
         report_all       => $o->get('report-all'),
         report_histogram => $o->get('report-histogram'),
      },
      num_format     => "# %-${label_width}s %3s %7s %7s %7s %7s %7s %7s %7s",
      bool_format    => "# %-${label_width}s %3d%% yes, %3d%% no",
      string_format  => "# %-${label_width}s %s",
      hidden_attrib  => {   # Don't sort/print these attribs in the reports.
         arg         => 1, # They're usually handled specially, or not
         fingerprint => 1, # printed at all.
         pos_in_log  => 1,
         ts          => 1,
      },
   };
   return $self;
}

# Arguments:
#   * reports       arrayref: reports to print
#   * ea            obj: EventAggregator
#   * worst         arrayref: worst items
#   * orderby       scalar: attrib worst items ordered by
#   * groupby       scalar: attrib worst items grouped by
# Optional arguments:
#   * other         arrayref: other items (that didn't make it into top worst)
#   * files         arrayref: files read for input
#   * group         hashref: don't add blank line between these reports
#                            if they appear together
# Prints the given reports (rusage, heade (global), query_report, etc.) in
# the given order.  These usually come from mk-query-digest --report-format.
# Most of the required args are for header() and query_report().
sub print_reports {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(reports ea worst orderby groupby) ) {
      die "I need a $arg argument" unless exists $args{$arg};
   }
   my $reports = $args{reports};
   my $group   = $args{group};
   my $last_report;

   foreach my $report ( @$reports ) {
      PTDEBUG && _d('Printing', $report, 'report'); 
      my $report_output = $self->$report(%args);
      if ( $report_output ) {
         print "\n"
            if !$last_report || !($group->{$last_report} && $group->{$report});
         print $report_output;
      }
      else {
         PTDEBUG && _d('No', $report, 'report');
      }
      $last_report = $report;
   }

   return;
}

sub rusage {
   my ( $self ) = @_;
   my ( $rss, $vsz, $user, $system ) = ( 0, 0, 0, 0 );
   my $rusage = '';
   eval {
      my $mem = `ps -o rss,vsz -p $PID 2>&1`;
      ( $rss, $vsz ) = $mem =~ m/(\d+)/g;
      ( $user, $system ) = times();
      $rusage = sprintf "# %s user time, %s system time, %s rss, %s vsz\n",
         micro_t( $user,   p_s => 1, p_ms => 1 ),
         micro_t( $system, p_s => 1, p_ms => 1 ),
         shorten( ($rss || 0) * 1_024 ),
         shorten( ($vsz || 0) * 1_024 );
   };
   if ( $EVAL_ERROR ) {
      PTDEBUG && _d($EVAL_ERROR);
   }
   return $rusage ? $rusage : "# Could not get rusage\n";
}

sub date {
   my ( $self ) = @_;
   return "# Current date: " . (scalar localtime) . "\n";
}

sub hostname {
   my ( $self ) = @_;
   my $hostname = `hostname`;
   if ( $hostname ) {
      chomp $hostname;
      return "# Hostname: $hostname\n";
   }
   return;
}

sub files {
   my ( $self, %args ) = @_;
   if ( $args{files} ) {
      return "# Files: " . join(', ', map { $_->{name} } @{$args{files}}) . "\n";
   }
   return;
}

# Arguments:
#   * ea         obj: EventAggregator
#   * orderby    scalar: attrib items ordered by
# Optional arguments:
#   * select     arrayref: attribs to print, mostly for testing
# Print a report about the global statistics in the EventAggregator.
# Formerly called "global_report()."
sub header {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea orderby) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $ea      = $args{ea};
   my $orderby = $args{orderby};
   my $results = $ea->results();
   my @result;

   # Get global count
   my $global_cnt = $results->{globals}->{$orderby}->{cnt} || 0;

   # Calculate QPS (queries per second) by looking at the min/max timestamp.
   my ($qps, $conc) = (0, 0);
   if ( $global_cnt && $results->{globals}->{ts}
      && ($results->{globals}->{ts}->{max} || '')
         gt ($results->{globals}->{ts}->{min} || '')
   ) {
      eval {
         my $min  = parse_timestamp($results->{globals}->{ts}->{min});
         my $max  = parse_timestamp($results->{globals}->{ts}->{max});
         my $diff = unix_timestamp($max) - unix_timestamp($min);
         $qps     = $global_cnt / ($diff || 1);
         $conc    = $results->{globals}->{$args{orderby}}->{sum} / $diff;
      };
   }

   # First line
   PTDEBUG && _d('global_cnt:', $global_cnt, 'unique:',
      scalar keys %{$results->{classes}}, 'qps:', $qps, 'conc:', $conc);
   my $line = sprintf(
      '# Overall: %s total, %s unique, %s QPS, %sx concurrency ',
      shorten($global_cnt, d=>1_000),
      shorten(scalar keys %{$results->{classes}}, d=>1_000),
      shorten($qps  || 0, d=>1_000),
      shorten($conc || 0, d=>1_000));
   $line .= ('_' x (LINE_LENGTH - length($line) + $self->label_width() - 12));
   push @result, $line;

   # Second line: time range
   if ( my $ts = $results->{globals}->{ts} ) {
      my $time_range = $self->format_time_range($ts) || "unknown";
      push @result, "# Time range: $time_range";
   }

   # Third line: rate limiting, if any
   if ( $results->{globals}->{rate_limit} ) {
      print "# Rate limits apply\n";
   }

   # Global column headers
   push @result, $self->make_global_header();

   # Sort the attributes, removing any hidden attributes.
   my $attribs = $self->sort_attribs( $ea );

   foreach my $type ( qw(num innodb) ) {
      # Add "InnoDB:" sub-header before grouped InnoDB_* attributes.
      if ( $type eq 'innodb' && @{$attribs->{$type}} ) {
         push @result, "# InnoDB:";
      };

      NUM_ATTRIB:
      foreach my $attrib ( @{$attribs->{$type}} ) {
         next unless exists $results->{globals}->{$attrib};
         my $store   = $results->{globals}->{$attrib};
         my $metrics = $ea->stats()->{globals}->{$attrib};
         my $func    = $attrib =~ m/time|wait$/ ? \&micro_t : \&shorten;
         my @values  = ( 
            @{$store}{qw(sum min max)},
            $store->{sum} / $store->{cnt},
            @{$metrics}{qw(pct_95 stddev median)},
         );
         @values = map { defined $_ ? $func->($_) : '' } @values;

         push @result,
            sprintf $self->{num_format},
               $self->make_label($attrib), '', @values;
      }
   }

   if ( @{$attribs->{bool}} ) {
      push @result, "# Boolean:";
      my $printed_bools = 0;
      BOOL_ATTRIB:
      foreach my $attrib ( @{$attribs->{bool}} ) {
         next unless exists $results->{globals}->{$attrib};

         my $store = $results->{globals}->{$attrib};
         if ( $store->{sum} > 0 ) { 
            push @result,
               sprintf $self->{bool_format},
                  $self->make_label($attrib), $self->bool_percents($store);
            $printed_bools = 1;
         }
      }
      pop @result unless $printed_bools;
   }

   return join("\n", map { s/\s+$//; $_ } @result) . "\n";
}

sub query_report_values {
   my ($self, %args) = @_;
   foreach my $arg ( qw(ea worst orderby groupby) ) {
      die "I need a $arg argument" unless defined $arg;
   }
   my $ea      = $args{ea};
   my $groupby = $args{groupby};
   my $worst   = $args{worst};

   my $q   = $self->Quoter;
   my $qv  = $self->{QueryReview};
   my $qr  = $self->{QueryRewriter};

   my @values;
   # Print each worst item: its stats/metrics (sum/min/max/95%/etc.),
   # Query_time distro chart, tables, EXPLAIN, fingerprint, etc.
   # Items are usually unique queries/fingerprints--depends on how
   # the events were grouped.
   ITEM:
   foreach my $top_event ( @$worst ) {
      my $item       = $top_event->[0];
      my $reason     = $args{explain_why} ? $top_event->[1] : '';
      my $rank       = $top_event->[2];
      my $stats      = $ea->results->{classes}->{$item};
      my $sample     = $ea->results->{samples}->{$item};
      my $samp_query = $sample->{arg} || '';

      my %item_vals = (
         item       => $item,
         samp_query => $samp_query,
         rank       => ($rank || 0),
         reason     => $reason,
      );

      # ###############################################################
      # Possibly skip item for --review.
      # ###############################################################
      my $review_vals;
      if ( $qv ) {
         $review_vals = $qv->get_review_info($item);
         next ITEM if $review_vals->{reviewed_by} && !$self->{options}->{report_all};
         for my $col ( $qv->review_cols() ) {
            push @{$item_vals{review_vals}}, [$col, $review_vals->{$col}];
         }
      }

      $item_vals{default_db} = $sample->{db}       ? $sample->{db}
                              : $stats->{db}->{unq} ? keys %{$stats->{db}->{unq}}
                              :                       undef;
      $item_vals{tables} = [$self->{QueryParser}->extract_tables(
            query      => $samp_query,
            default_db => $item_vals{default_db},
            Quoter     => $self->Quoter,
         )];

      if ( $samp_query && ($args{variations} && @{$args{variations}}) ) {
         $item_vals{crc} = crc32($samp_query);
      }

      push @values, \%item_vals;
   }
   return \@values;
}

# Arguments:
#   * ea       obj: EventAggregator
#   * worst    arrayref: worst items
#   * orderby  scalar: attrib worst items ordered by
#   * groupby  scalar: attrib worst items grouped by
# Optional arguments:
#   * select       arrayref: attribs to print, mostly for test
#   * explain_why  bool: print reason why item is reported
#   * print_header  bool: "Report grouped by" header
sub query_report {
   my ( $self, %args ) = @_;

   my $ea      = $args{ea};
   my $groupby = $args{groupby};
   my $report_values = $self->query_report_values(%args);

   my $qr  = $self->{QueryRewriter};

   my $report = '';

   if ( $args{print_header} ) {
      $report .= "# " . ( '#' x 72 ) . "\n"
               . "# Report grouped by $groupby\n"
               . '# ' . ( '#' x 72 ) . "\n\n";
   }

   # Sort the attributes, removing any hidden attributes.
   my $attribs = $self->sort_attribs( $ea );

   # Print each worst item: its stats/metrics (sum/min/max/95%/etc.),
   # Query_time distro chart, tables, EXPLAIN, fingerprint, etc.
   # Items are usually unique queries/fingerprints--depends on how
   # the events were grouped.
   ITEM:
   foreach my $vals ( @$report_values ) {
      my $item = $vals->{item};
      # ###############################################################
      # Print the standard query analysis report.
      # ###############################################################
      $report .= "\n" if $vals->{rank} > 1;  # space between each event report
      $report .= $self->event_report(
         %args,
         item    => $item,
         sample  => $ea->results->{samples}->{$item},
         rank    => $vals->{rank},
         reason  => $vals->{reason},
         attribs => $attribs,
         db      => $vals->{default_db},
      );

      if ( $self->{options}->{report_histogram} ) {
         $report .= $self->chart_distro(
            %args,
            attrib => $self->{options}->{report_histogram},
            item   => $vals->{item},
         );
      }

      if ( $vals->{review_vals} ) {
         # Print the review information that is already in the table
         # before putting anything new into the table.
         $report .= "# Review information\n";
         foreach my $elem ( @{$vals->{review_vals}} ) {
            my ($col, $val) = @$elem;
            if ( !$val || $val ne '0000-00-00 00:00:00' ) { # issue 202
               $report .= sprintf "# %13s: %-s\n", $col, ($val ? $val : '');
            }
         }
      }

      if ( $groupby eq 'fingerprint' ) {
         # Shorten it if necessary (issue 216 and 292).           
         my $samp_query = $qr->shorten($vals->{samp_query}, $self->{options}->{shorten})
            if $self->{options}->{shorten};

         # Print query fingerprint.
         PTDEBUG && _d("Fingerprint\n#    $vals->{item}\n");

         # Print tables used by query.
         $report .= $self->tables_report(@{$vals->{tables}});

         # Print sample (worst) query's CRC % 1_000.  We mod 1_000 because
         # that's actually the value stored in the ea, not the full checksum.
         # So the report will print something like,
         #   # arg crc      685 (2/66%), 159 (1/33%)
         # Thus we want our "CRC" line to be 685 and not 18547302820.
         if ( $vals->{crc} ) {
            $report.= "# CRC " . ($vals->{crc} % 1_000) . "\n";
         }

         my $log_type = $args{log_type} || '';
         my $mark     = '\G';

         if ( $item =~ m/^(?:[\(\s]*select|insert|replace)/ ) {
            if ( $item =~ m/^(?:insert|replace)/ ) { # No EXPLAIN
               $report .= "$samp_query${mark}\n";
            }
            else {
               $report .= "# EXPLAIN /*!50100 PARTITIONS*/\n$samp_query${mark}\n"; 
               $report .= $self->explain_report($samp_query, $vals->{default_db});
            }
         }
         else {
            $report .= "$samp_query${mark}\n"; 
            my $converted = $qr->convert_to_select($samp_query);
            if ( $converted
                 && $converted =~ m/^[\(\s]*select/i ) {
               # It converted OK to a SELECT
               $report .= "# Converted for EXPLAIN\n# EXPLAIN /*!50100 PARTITIONS*/\n$converted${mark}\n";
            }
         }
      }
      else {
         if ( $groupby eq 'tables' ) {
            my ( $db, $tbl ) = $self->Quoter->split_unquote($item);
            $report .= $self->tables_report([$db, $tbl]);
         }
         $report .= "$item\n";
      }
   }

   return $report;
}

# Arguments:
#   * ea          obj: EventAggregator
#   * item        scalar: Item in ea results
#   * orderby     scalar: attribute that events are ordered by
# Optional arguments:
#   * select      arrayref: attribs to print, mostly for testing
#   * reason      scalar: why this item is being reported (top|outlier)
#   * rank        scalar: item rank among the worst
# Print a report about the statistics in the EventAggregator.
# Called by query_report().
sub event_report_values {
   my ($self, %args) = @_;

   my $ea   = $args{ea};
   my $item = $args{item};
   my $orderby = $args{orderby};
   my $results = $ea->results();

   my %vals;

   # Return unless the item exists in the results (it should).
   my $store = $results->{classes}->{$item};

   return unless $store;

   # Pick the first attribute to get counts
   my $global_cnt = $results->{globals}->{$orderby}->{cnt};
   my $class_cnt  = $store->{$orderby}->{cnt};

   # Calculate QPS (queries per second) by looking at the min/max timestamp.
   my ($qps, $conc) = (0, 0);
   if ( $global_cnt && $store->{ts}
      && ($store->{ts}->{max} || '')
         gt ($store->{ts}->{min} || '')
   ) {
      eval {
         my $min  = parse_timestamp($store->{ts}->{min});
         my $max  = parse_timestamp($store->{ts}->{max});
         my $diff = unix_timestamp($max) - unix_timestamp($min);
         $qps     = $class_cnt / $diff;
         $conc    = $store->{$orderby}->{sum} / $diff;
      };
   }

   $vals{groupby}     = $ea->{groupby};
   $vals{qps}         = $qps  || 0;
   $vals{concurrency} = $conc || 0;
   $vals{checksum}    = make_checksum($item);
   $vals{pos_in_log}  = $results->{samples}->{$item}->{pos_in_log} || 0;
   $vals{reason}      = $args{reason};
   $vals{variance_to_mean} = do {
      my $query_time = $ea->metrics(where => $item, attrib => 'Query_time');
      $query_time->{stddev}**2 / ($query_time->{avg} || 1)
   };

   $vals{counts} = {
      class_cnt        => $class_cnt,
      global_cnt       => $global_cnt,
   };

   if ( my $ts = $store->{ts}) {
      $vals{time_range} = $self->format_time_range($ts) || "unknown";
   }

   # Sort the attributes, removing any hidden attributes, if they're not
   # already given to us.  In mk-query-digest, this sub is called from
   # query_report(), but in testing it's called directly.  query_report()
   # will sort and pass the attribs so they're not for every event.
   my $attribs = $args{attribs};
   if ( !$attribs ) {
      $attribs = $self->sort_attribs( $ea );
   }

   $vals{attributes} = { map { $_ => [] } qw(num innodb bool string) };

   foreach my $type ( qw(num innodb) ) {
      # Add "InnoDB:" sub-header before grouped InnoDB_* attributes.

      NUM_ATTRIB:
      foreach my $attrib ( @{$attribs->{$type}} ) {
         next NUM_ATTRIB unless exists $store->{$attrib};
         my $vals = $store->{$attrib};
         next unless scalar %$vals;

         my $pct;
         my $func    = $attrib =~ m/time|wait$/ ? \&micro_t : \&shorten;
         my $metrics = $ea->stats()->{classes}->{$item}->{$attrib};
         my @values = (
            @{$vals}{qw(sum min max)},
            $vals->{sum} / $vals->{cnt},
            @{$metrics}{qw(pct_95 stddev median)},
         );
         @values = map { defined $_ ? $func->($_) : '' } @values;
         $pct   = percentage_of(
            $vals->{sum}, $results->{globals}->{$attrib}->{sum});

         push @{$vals{attributes}{$type}},
               [ $attrib, $pct, @values ];
      }
   }

   if ( @{$attribs->{bool}} ) {
      BOOL_ATTRIB:
      foreach my $attrib ( @{$attribs->{bool}} ) {
         next BOOL_ATTRIB unless exists $store->{$attrib};
         my $vals = $store->{$attrib};
         next unless scalar %$vals;

         if ( $vals->{sum} > 0 ) {
            push @{$vals{attributes}{bool}},
                  [ $attrib, $self->bool_percents($vals) ];
         }
      }
   }

   if ( @{$attribs->{string}} ) {
      STRING_ATTRIB:
      foreach my $attrib ( @{$attribs->{string}} ) {
         next STRING_ATTRIB unless exists $store->{$attrib};
         my $vals = $store->{$attrib};
         next unless scalar %$vals;

         push @{$vals{attributes}{string}},
               [ $attrib, $vals ];
      }
   }


   return \%vals;
}

# TODO I maybe've broken the groupby report

sub event_report {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea item orderby) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $item = $args{item};
   my $val  = $self->event_report_values(%args);
   my @result;

   return "# No such event $item\n" unless $val;

   # First line like:
   # Query 1: 9 QPS, 0x concurrency, ID 0x7F7D57ACDD8A346E at byte 5 ________
   my $line = sprintf(
      '# %s %d: %s QPS, %sx concurrency, ID 0x%s at byte %.f ',
      ($val->{groupby} eq 'fingerprint' ? 'Query' : 'Item'),
      $args{rank} || 0,
      shorten($val->{qps}, d=>1_000),
      shorten($val->{concurrency}, d=>1_000),
      $val->{checksum},
      $val->{pos_in_log},
   );
   $line .= ('_' x (LINE_LENGTH - length($line) + $self->label_width() - 12));
   push @result, $line;

   # Second line: reason why this class is being reported.
   if ( $val->{reason} ) {
      push @result,
         "# This item is included in the report because it matches "
            . ($val->{reason} eq 'top' ? '--limit.' : '--outliers.');
   }

   # Third line: Variance-to-mean (V/M) ratio, like:
   # Scores: V/M = 1.5
   push @result,
      sprintf("# Scores: V/M = %.2f", $val->{variance_to_mean} );

   # Time range
   if ( $val->{time_range} ) {
      push @result, "# Time range: $val->{time_range}";
   }

   # Column header line
   push @result, $self->make_event_header();

   # Count line
   push @result,
      sprintf $self->{num_format}, 'Count',
         percentage_of($val->{counts}{class_cnt}, $val->{counts}{global_cnt}),
         $val->{counts}{class_cnt},
         map { '' } (1..8);


   my $attribs = $val->{attributes};

   foreach my $type ( qw(num innodb) ) {
      # Add "InnoDB:" sub-header before grouped InnoDB_* attributes.
      if ( $type eq 'innodb' && @{$attribs->{$type}} ) {
         push @result, "# InnoDB:";
      };

      NUM_ATTRIB:
      foreach my $attrib ( @{$attribs->{$type}} ) {
         my ($attrib_name, @vals) = @$attrib;
         push @result,
            sprintf $self->{num_format},
               $self->make_label($attrib_name), @vals;
      }
   }

   if ( @{$attribs->{bool}} ) {
      push @result, "# Boolean:";
      BOOL_ATTRIB:
      foreach my $attrib ( @{$attribs->{bool}} ) {
         my ($attrib_name, @vals) = @$attrib;
         push @result,
            sprintf $self->{bool_format},
               $self->make_label($attrib_name), @vals;
      }
   }

   if ( @{$attribs->{string}} ) {
      push @result, "# String:";
      STRING_ATTRIB:
      foreach my $attrib ( @{$attribs->{string}} ) {
         my ($attrib_name, $vals) = @$attrib;
         push @result,
            sprintf $self->{string_format},
               $self->make_label($attrib_name),
               $self->format_string_list($attrib_name, $vals, $val->{counts}{class_cnt});
      }
   }


   return join("\n", map { s/\s+$//; $_ } @result) . "\n";
}

# Arguments:
#  * ea      obj: EventAggregator
#  * item    scalar: item in ea results
#  * attrib  scalar: item's attribute to chart
# Creates a chart of value distributions in buckets.  Right now it bucketizes
# into 8 buckets, powers of ten starting with .000001.
sub chart_distro {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea item attrib) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $ea     = $args{ea};
   my $item   = $args{item};
   my $attrib = $args{attrib};

   my $results = $ea->results();
   my $store   = $results->{classes}->{$item}->{$attrib};
   my $vals    = $store->{all};
   return "" unless defined $vals && scalar %$vals;

   # TODO: this is broken.
   my @buck_tens = $ea->buckets_of(10);
   my @distro = map { 0 } (0 .. 7);

   # See similar code in EventAggregator::_calc_metrics() or
   # http://code.google.com/p/maatkit/issues/detail?id=866
   my @buckets = map { 0 } (0..999);
   map { $buckets[$_] = $vals->{$_} } keys %$vals;
   $vals = \@buckets;  # repoint vals from given hashref to our array

   map { $distro[$buck_tens[$_]] += $vals->[$_] } (1 .. @$vals - 1);

   my $vals_per_mark; # number of vals represented by 1 #-mark
   my $max_val        = 0;
   my $max_disp_width = 64;
   my $bar_fmt        = "# %5s%s";
   my @distro_labels  = qw(1us 10us 100us 1ms 10ms 100ms 1s 10s+);
   my @results        = "# $attrib distribution";

   # Find the distro with the most values. This will set
   # vals_per_mark and become the bar at max_disp_width.
   foreach my $n_vals ( @distro ) {
      $max_val = $n_vals if $n_vals > $max_val;
   }
   $vals_per_mark = $max_val / $max_disp_width;

   foreach my $i ( 0 .. $#distro ) {
      my $n_vals  = $distro[$i];
      my $n_marks = $n_vals / ($vals_per_mark || 1);

      # Always print at least 1 mark for any bucket that has at least
      # 1 value. This skews the graph a tiny bit, but it allows us to
      # see all buckets that have values.
      $n_marks = 1 if $n_marks < 1 && $n_vals > 0;

      my $bar = ($n_marks ? '  ' : '') . '#' x $n_marks;
      push @results, sprintf $bar_fmt, $distro_labels[$i], $bar;
   }

   return join("\n", @results) . "\n";
}

# Profile subreport (issue 381).
# Arguments:
#   * ea            obj: EventAggregator
#   * worst         arrayref: worst items
#   * groupby       scalar: attrib worst items grouped by
# Optional arguments:
#   * other            arrayref: other items (that didn't make it into top worst)
#   * distill_args     hashref: extra args for distill()
sub profile {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea worst groupby) ) {
      die "I need a $arg argument" unless defined $arg;
   }
   my $ea      = $args{ea};
   my $worst   = $args{worst};
   my $other   = $args{other};
   my $groupby = $args{groupby};

   my $qr  = $self->{QueryRewriter};

   # Total response time of all events.
   my $results = $ea->results();
   my $total_r = $results->{globals}->{Query_time}->{sum} || 0;

   my @profiles;
   foreach my $top_event ( @$worst ) {
      my $item       = $top_event->[0];
      my $rank       = $top_event->[2];
      my $stats      = $ea->results->{classes}->{$item};
      my $sample     = $ea->results->{samples}->{$item};
      my $samp_query = $sample->{arg} || '';
      my $query_time = $ea->metrics(where => $item, attrib => 'Query_time');

      my %profile    = (
         rank   => $rank,
         r      => $stats->{Query_time}->{sum},
         cnt    => $stats->{Query_time}->{cnt},
         sample => $groupby eq 'fingerprint' ?
                    $qr->distill($samp_query, %{$args{distill_args}}) : $item,
         id     => $groupby eq 'fingerprint' ? make_checksum($item)   : '',
         vmr    => ($query_time->{stddev}**2) / ($query_time->{avg} || 1),
      ); 

      push @profiles, \%profile;
   }

   my $report = $self->ReportFormatter();
   $report->title('Profile');
   my @cols = (
      { name => 'Rank',          right_justify => 1,             },
      { name => 'Query ID',                                      },
      { name => 'Response time', right_justify => 1,             },
      { name => 'Calls',         right_justify => 1,             },
      { name => 'R/Call',        right_justify => 1,             },
      { name => 'V/M',           right_justify => 1, width => 5, },
      { name => 'Item',                                          },
   );
   $report->set_columns(@cols);

   foreach my $item ( sort { $a->{rank} <=> $b->{rank} } @profiles ) {
      my $rt  = sprintf('%10.4f', $item->{r});
      my $rtp = sprintf('%4.1f%%', $item->{r} / ($total_r || 1) * 100);
      my $rc  = sprintf('%8.4f', $item->{r} / $item->{cnt});
      my $vmr = sprintf('%4.2f', $item->{vmr});
      my @vals = (
         $item->{rank},
         "0x$item->{id}",
         "$rt $rtp",
         $item->{cnt},
         $rc,
         $vmr,
         $item->{sample},
      );
      $report->add_line(@vals);
   }

   # The last line of the profile is for all the other, non-worst items.
   # http://code.google.com/p/maatkit/issues/detail?id=1043
   if ( $other && @$other ) {
      my $misc = {
            r   => 0,
            cnt => 0,
      };
      foreach my $other_event ( @$other ) {
         my $item      = $other_event->[0];
         my $stats     = $ea->results->{classes}->{$item};
         $misc->{r}   += $stats->{Query_time}->{sum};
         $misc->{cnt} += $stats->{Query_time}->{cnt};
      }
      my $rt  = sprintf('%10.4f', $misc->{r});
      my $rtp = sprintf('%4.1f%%', $misc->{r} / ($total_r || 1) * 100);
      my $rc  = sprintf('%8.4f', $misc->{r} / $misc->{cnt});
      $report->add_line(
         "MISC",
         "0xMISC",
         "$rt $rtp",
         $misc->{cnt},
         $rc,
         '0.0',  # variance-to-mean ratio is not meaningful here
         "<".scalar @$other." ITEMS>",
      );
   }

   return $report->get_report();
}

# Prepared statements subreport (issue 740).
# Arguments:
#   * ea            obj: EventAggregator
#   * worst         arrayref: worst items
#   * groupby       scalar: attrib worst items grouped by
# Optional arguments:
#   * distill_args  hashref: extra args for distill()
sub prepared {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea worst groupby) ) {
      die "I need a $arg argument" unless defined $arg;
   }
   my $ea      = $args{ea};
   my $worst   = $args{worst};
   my $groupby = $args{groupby};

   my $qr = $self->{QueryRewriter};

   my @prepared;       # prepared statements
   my %seen_prepared;  # report each PREP-EXEC pair once
   my $total_r = 0;

   foreach my $top_event ( @$worst ) {
      my $item       = $top_event->[0];
      my $rank       = $top_event->[2];
      my $stats      = $ea->results->{classes}->{$item};
      my $sample     = $ea->results->{samples}->{$item};
      my $samp_query = $sample->{arg} || '';

      $total_r += $stats->{Query_time}->{sum};
      next unless $stats->{Statement_id} && $item =~ m/^(?:prepare|execute) /;

      # Each PREPARE (probably) has some EXECUTE and each EXECUTE (should)
      # have some PREPARE.  But these are only the top N events so we can get
      # here a PREPARE but not its EXECUTE or vice-versa.  The prepared
      # statements report requires both so this code gets the missing pair
      # from the ea stats.
      my ($prep_stmt, $prep, $prep_r, $prep_cnt);
      my ($exec_stmt, $exec, $exec_r, $exec_cnt);

      if ( $item =~ m/^prepare / ) {
         $prep_stmt           = $item;
         ($exec_stmt = $item) =~ s/^prepare /execute /;
      }
      else {
         ($prep_stmt = $item) =~ s/^execute /prepare /;
         $exec_stmt           = $item;
      }

      # Report each PREPARE/EXECUTE pair once.
      if ( !$seen_prepared{$prep_stmt}++ ) {
         if ( exists $ea->results->{classes}->{$exec_stmt} ) {
            $exec     = $ea->results->{classes}->{$exec_stmt};
            $exec_r   = $exec->{Query_time}->{sum};
            $exec_cnt = $exec->{Query_time}->{cnt};
         }
         else {
            PTDEBUG && _d('Statement prepared but not executed:', $item);
            $exec_r   = 0;
            $exec_cnt = 0;
         }

         if ( exists $ea->results->{classes}->{$prep_stmt} ) {
            $prep     = $ea->results->{classes}->{$prep_stmt};
            $prep_r   = $prep->{Query_time}->{sum};
            $prep_cnt = scalar keys %{$prep->{Statement_id}->{unq}},
         }
         else {
            PTDEBUG && _d('Statement executed but not prepared:', $item);
            $prep_r   = 0;
            $prep_cnt = 0;
         }

         push @prepared, {
            prep_r   => $prep_r, 
            prep_cnt => $prep_cnt,
            exec_r   => $exec_r,
            exec_cnt => $exec_cnt,
            rank     => $rank,
            sample   => $groupby eq 'fingerprint'
                          ? $qr->distill($samp_query, %{$args{distill_args}})
                          : $item,
            id       => $groupby eq 'fingerprint' ? make_checksum($item)
                                                  : '',
         };
      }
   }

   # Return unless there are prepared statements to report.
   return unless scalar @prepared;

   my $report = $self->ReportFormatter();
   $report->title('Prepared statements');
   $report->set_columns(
      { name => 'Rank',          right_justify => 1, },
      { name => 'Query ID',                          },
      { name => 'PREP',          right_justify => 1, },
      { name => 'PREP Response', right_justify => 1, },
      { name => 'EXEC',          right_justify => 1, },
      { name => 'EXEC Response', right_justify => 1, },
      { name => 'Item',                              },
   );

   foreach my $item ( sort { $a->{rank} <=> $b->{rank} } @prepared ) {
      my $exec_rt  = sprintf('%10.4f', $item->{exec_r});
      my $exec_rtp = sprintf('%4.1f%%',$item->{exec_r}/($total_r || 1) * 100);
      my $prep_rt  = sprintf('%10.4f', $item->{prep_r});
      my $prep_rtp = sprintf('%4.1f%%',$item->{prep_r}/($total_r || 1) * 100);
      $report->add_line(
         $item->{rank},
         "0x$item->{id}",
         $item->{prep_cnt} || 0,
         "$prep_rt $prep_rtp",
         $item->{exec_cnt} || 0,
         "$exec_rt $exec_rtp",
         $item->{sample},
      );
   }
   return $report->get_report();
}

sub make_global_header {
   my ( $self ) = @_;
   my @lines;

   # First line: 
   # Attribute          total     min     max     avg     95%  stddev  median
   push @lines,
      sprintf $self->{num_format}, "Attribute", '', @{$self->global_headers()};

   # Underline first line:
   # =========        ======= ======= ======= ======= ======= ======= =======
   # The numbers 7, 7, 7, etc. are the field widths from make_header().
   # Hard-coded values aren't ideal but this code rarely changes.
   push @lines,
      sprintf $self->{num_format},
         (map { "=" x $_ } $self->label_width()),
         (map { " " x $_ } qw(3)),  # no pct column in global header
         (map { "=" x $_ } qw(7 7 7 7 7 7 7));

   # End result should be like:
   # Attribute          total     min     max     avg     95%  stddev  median
   # =========        ======= ======= ======= ======= ======= ======= =======
   return @lines;
}

sub make_event_header {
   my ( $self ) = @_;

   # Event headers are all the same so we just make them once.
   return @{$self->{event_header_lines}} if $self->{event_header_lines};

   my @lines;
   push @lines,
      sprintf $self->{num_format}, "Attribute", @{$self->event_headers()};

   # The numbers 6, 7, 7, etc. are the field widths from make_header().
   # Hard-coded values aren't ideal but this code rarely changes.
   push @lines,
      sprintf $self->{num_format},
         map { "=" x $_ } ($self->label_width(), qw(3 7 7 7 7 7 7 7));

   # End result should be like:
   # Attribute    pct   total     min     max     avg     95%  stddev  median
   # ========= ====== ======= ======= ======= ======= ======= ======= =======
   $self->{event_header_lines} = \@lines;
   return @lines;
}

# Convert attribute names into labels
sub make_label {
   my ( $self, $val ) = @_;
   return '' unless $val;

   $val =~ s/_/ /g;

   if ( $val =~ m/^InnoDB/ ) {
      $val =~ s/^InnoDB //;
      $val = $val eq 'trx id' ? "InnoDB trxID"
           : substr($val, 0, $self->label_width());
   }

   $val = $val eq 'user'            ? 'Users'
        : $val eq 'db'              ? 'Databases'
        : $val eq 'Query time'      ? 'Exec time'
        : $val eq 'host'            ? 'Hosts'
        : $val eq 'Error no'        ? 'Errors'
        : $val eq 'bytes'           ? 'Query size'
        : $val eq 'Tmp disk tables' ? 'Tmp disk tbl'
        : $val eq 'Tmp table sizes' ? 'Tmp tbl size'
        : substr($val, 0, $self->label_width);

   return $val;
}

sub bool_percents {
   my ( $self, $vals ) = @_;
   # Since the value is either 1 or 0, the sum is the number of
   # all true events and the number of false events is the total
   # number of events minus those that were true.
   my $p_true  = percentage_of($vals->{sum},  $vals->{cnt});
   my $p_false = percentage_of(($vals->{cnt} - $vals->{sum}), $vals->{cnt});
   return $p_true, $p_false;
}

# Does pretty-printing for lists of strings like users, hosts, db.
sub format_string_list {
   my ( $self, $attrib, $vals, $class_cnt ) = @_;
   
   # Only class result values have unq.  So if unq doesn't exist,
   # then we've been given global values.
   if ( !exists $vals->{unq} ) {
      return ($vals->{cnt});
   }

   my $show_all = $self->show_all();

   my $cnt_for = $vals->{unq};
   if ( 1 == keys %$cnt_for ) {
      my ($str) = keys %$cnt_for;
      # - 30 for label, spacing etc.
      $str = substr($str, 0, LINE_LENGTH - 30) . '...'
         if length $str > LINE_LENGTH - 30;
      return $str;
   }
   my $line = '';
   my @top = sort { $cnt_for->{$b} <=> $cnt_for->{$a} || $a cmp $b }
                  keys %$cnt_for;
   my $i = 0;
   foreach my $str ( @top ) {
      my $print_str;
      if ( $str =~ m/(?:\d+\.){3}\d+/ ) {
         $print_str = $str;  # Do not shorten IP addresses.
      }
      elsif ( length $str > MAX_STRING_LENGTH ) {
         $print_str = substr($str, 0, MAX_STRING_LENGTH) . '...';
      }
      else {
         $print_str = $str;
      }
      my $p = percentage_of($cnt_for->{$str}, $class_cnt);
      $print_str .= " ($cnt_for->{$str}/$p%)";
      if ( !$show_all->{$attrib} ) {
         last if (length $line) + (length $print_str)  > LINE_LENGTH - 27;
      }
      $line .= "$print_str, ";
      $i++;
   }

   $line =~ s/, $//;

   if ( $i < @top ) {
      $line .= "... " . (@top - $i) . " more";
   }

   return $line;
}

sub sort_attribs {
   my ( $self, $ea ) = @_;
   my $attribs = $ea->get_attributes();
   return unless $attribs && @$attribs;
   PTDEBUG && _d("Sorting attribs:", @$attribs);

   # Sort order for numeric attribs.  Attribs not listed here come after these
   # in alphabetical order.
   my @num_order = qw(
      Query_time
      Exec_orig_time
      Transmit_time
      Lock_time
      Rows_sent
      Rows_examined
      Rows_affected
      Rows_read
      Bytes_sent
      Merge_passes
      Tmp_tables
      Tmp_disk_tables
      Tmp_table_sizes
      bytes
   );
   my $i         = 0;
   my %num_order = map { $_ => $i++ } @num_order;

   my (@num, @innodb, @bool, @string);
   ATTRIB:
   foreach my $attrib ( @$attribs ) {
      next if $self->{hidden_attrib}->{$attrib};

      # Default type is string in EventAggregator::make_handler().
      my $type = $ea->type_for($attrib) || 'string';
      if ( $type eq 'num' ) {
         if ( $attrib =~ m/^InnoDB_/ ) {
            push @innodb, $attrib;
         }
         else {
            push @num, $attrib;
         }
      }
      elsif ( $type eq 'bool' ) {
         push @bool, $attrib;
      }
      elsif ( $type eq 'string' ) {
         push @string, $attrib;
      }
      else {
         PTDEBUG && _d("Unknown attrib type:", $type, "for", $attrib);
      }
   }

   @num    = sort { pref_sort($a, $num_order{$a}, $b, $num_order{$b}) } @num;
   @innodb = sort { uc $a cmp uc $b } @innodb;
   @bool   = sort { uc $a cmp uc $b } @bool;
   @string = sort { uc $a cmp uc $b } @string;

   return {
      num     => \@num,
      innodb  => \@innodb,
      string  => \@string,
      bool    => \@bool,
   };
}

sub pref_sort {
   my ( $attrib_a, $order_a, $attrib_b, $order_b ) = @_;

   # Neither has preferred order so sort by attrib name alphabetically.
   if ( !defined $order_a && !defined $order_b ) {
      return $attrib_a cmp $attrib_b;
   }

   # By have a preferred order so sort by their order.
   if ( defined $order_a && defined $order_b ) {
      return $order_a <=> $order_b;
   }

   # Only one has a preferred order so sort it first.
   if ( !defined $order_a ) {
      return 1;
   }
   else {
      return -1;
   }
}

# Gets a default database and a list of arrayrefs of [db, tbl] to print out
sub tables_report {
   my ( $self, @tables ) = @_;
   return '' unless @tables;
   my $q      = $self->Quoter();
   my $tables = "";
   foreach my $db_tbl ( @tables ) {
      my ( $db, $tbl ) = @$db_tbl;
      $tables .= '#    SHOW TABLE STATUS'
               . ($db ? " FROM `$db`" : '')
               . " LIKE '$tbl'\\G\n";
      $tables .= "#    SHOW CREATE TABLE "
               . $q->quote(grep { $_ } @$db_tbl)
               . "\\G\n";
   }
   return $tables ? "# Tables\n$tables" : "# No tables\n";
}

sub explain_report {
   my ( $self, $query, $db ) = @_;
   return '' unless $query;

   my $dbh = $self->{dbh};
   my $q   = $self->Quoter();
   my $qp  = $self->{QueryParser};
   return '' unless $dbh && $q && $qp;

   my $explain = '';
   eval {
      if ( !$qp->has_derived_table($query) ) {
         if ( $db ) {
            PTDEBUG && _d($dbh, "USE", $db);
            $dbh->do("USE " . $q->quote($db));
         }
         my $sth = $dbh->prepare("EXPLAIN /*!50100 PARTITIONS */ $query");
         $sth->execute();
         my $i = 1;
         while ( my @row = $sth->fetchrow_array() ) {
            $explain .= "# *************************** $i. "
                      . "row ***************************\n";
            foreach my $j ( 0 .. $#row ) {
               $explain .= sprintf "# %13s: %s\n", $sth->{NAME}->[$j],
                  defined $row[$j] ? $row[$j] : 'NULL';
            }
            $i++;  # next row number
         }
      }
   };
   if ( $EVAL_ERROR ) {
      PTDEBUG && _d("EXPLAIN failed:", $query, $EVAL_ERROR);
   }
   return $explain ? $explain : "# EXPLAIN failed: $EVAL_ERROR";
}

sub format_time_range {
   my ( $self, $vals ) = @_;
   my $min = parse_timestamp($vals->{min} || '');
   my $max = parse_timestamp($vals->{max} || '');

   if ( $min && $max && $min eq $max ) {
      return "all events occurred at $min";
   }

   # Remove common prefix (day).
   my ($min_day) = split(' ', $min) if $min;
   my ($max_day) = split(' ', $max) if $max;
   if ( ($min_day || '') eq ($max_day || '') ) {
      (undef, $max) = split(' ', $max);
   }

   return $min && $max ? "$min to $max" : '';
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
}
# ###########################################################################
# End QueryReportFormatter package
# ###########################################################################
