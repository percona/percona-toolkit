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
# EventAggregator package
# ###########################################################################
{
# Package: EventAggregator
# EventAggregator aggregates event values and calculates basic statistics.
package EventAggregator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use List::Util qw(min max);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# ###########################################################################
# Set up some constants for bucketing values.  It is impossible to keep all
# values seen in memory, but putting them into logarithmically scaled buckets
# and just incrementing the bucket each time works, although it is imprecise.
# See http://code.google.com/p/maatkit/wiki/EventAggregatorInternals.
# ###########################################################################
use constant BUCK_SIZE   => 1.05;
use constant BASE_LOG    => log(BUCK_SIZE);
use constant BASE_OFFSET => abs(1 - log(0.000001) / BASE_LOG); # 284.1617969
use constant NUM_BUCK    => 1000;
use constant MIN_BUCK    => .000001;

# Used in buckets_of() to map buckets of log10 to log1.05 buckets.
my @buck_vals = map { bucket_value($_); } (0..NUM_BUCK-1);

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   groupby - Attribute to group/aggregate classes by.
#   worst   - Attribute which defines the worst event in a class.
#             Samples of the worst attribute are saved.
#
# Optional Arguments:
#   attributes        - Hashref of attributes to aggregate.  Keys are attribute
#                       names used in the EventAggregator object and values are
#                       attribute names used to get values from events.
#                       Multiple attrib names in the arrayref specify alternate
#                       attrib names in the event.  Example:
#                       Fruit => ['apple', 'orange'].  An attrib called "Fruit"
#                       will be created using the event's "apple" value or,
#                       if that attrib doesn't exist, its "orange" value.
#                       If this option isn't specified, then then all attributes#                       are auto-detected and aggregated.
#   ignore_attributes - Arrayref of auto-detected attributes to ignore. 
#                       This does not apply to the attributes specified
#                       with the optional attributes option above.
#   unroll_limit      - If this many events have been processed and some
#                       handlers haven't been generated yet (due to lack
#                       of sample data), unroll the loop anyway. (default 1000)
#   attrib_limit      - Sanity limit for attribute values.  If the value
#                       exceeds the limit, use the last-seen for this class;
#                       if none, then 0.
#   type_for          - Hashref of attribute=>type pairs.  See $type in
#                       <make_handler()> for the list of types.
#
# Returns:
#   EventAggregator object
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(groupby worst) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $attributes = $args{attributes} || {};
   my $self = {
      groupby        => $args{groupby},
      detect_attribs => scalar keys %$attributes == 0 ? 1 : 0,
      all_attribs    => [ keys %$attributes ],
      ignore_attribs => {
         map  { $_ => $args{attributes}->{$_} }
         grep { $_ ne $args{groupby} }
         @{$args{ignore_attributes}}
      },
      attributes     => {
         map  { $_ => $args{attributes}->{$_} }
         grep { $_ ne $args{groupby} }
         keys %$attributes
      },
      alt_attribs    => {
         map  { $_ => make_alt_attrib(@{$args{attributes}->{$_}}) }
         grep { $_ ne $args{groupby} }
         keys %$attributes
      },
      worst          => $args{worst},
      unroll_limit   => $ENV{PT_QUERY_DIGEST_CHECK_ATTRIB_LIMIT} || 1000,
      attrib_limit   => $args{attrib_limit},
      result_classes => {},
      result_globals => {},
      result_samples => {},
      class_metrics  => {},
      global_metrics => {},
      n_events       => 0,
      unrolled_loops => undef,
      type_for       => { %{$args{type_for} || { Query_time => 'num' }} },
   };
   return bless $self, $class;
}

# Delete all collected data, but don't delete things like the generated
# subroutines.  Resetting aggregated data is an interesting little exercise.
# The generated functions that do aggregation have private namespaces with
# references to some of the data.  Thus, they will not necessarily do as
# expected if the stored data is simply wiped out.  Instead, it needs to be
# zeroed out without replacing the actual objects.
sub reset_aggregated_data {
   my ( $self ) = @_;
   foreach my $class ( values %{$self->{result_classes}} ) {
      foreach my $attrib ( values %$class ) {
         delete @{$attrib}{keys %$attrib};
      }
   }
   foreach my $class ( values %{$self->{result_globals}} ) {
      delete @{$class}{keys %$class};
   }
   delete @{$self->{result_samples}}{keys %{$self->{result_samples}}};
   $self->{n_events} = 0;
}

# Aggregate an event hashref's properties.  Code is built on the fly to do this,
# based on the values being passed in.  After code is built for every attribute
# (or 50 events are seen and we decide to give up) the little bits of code get
# unrolled into a whole subroutine to handle events.  For that reason, you can't
# re-use an instance.
sub aggregate {
   my ( $self, $event ) = @_;

   my $group_by = $event->{$self->{groupby}};
   return unless defined $group_by;

   $self->{n_events}++;
   PTDEBUG && _d('Event', $self->{n_events});

   # Run only unrolled loops if available.
   return $self->{unrolled_loops}->($self, $event, $group_by)
      if $self->{unrolled_loops};

   # For the first unroll_limit events, auto-detect new attribs and
   # run attrib handlers.
   if ( $self->{n_events} <= $self->{unroll_limit} ) {

      $self->add_new_attributes($event) if $self->{detect_attribs};

      ATTRIB:
      foreach my $attrib ( keys %{$self->{attributes}} ) {

         # Attrib auto-detection can add a lot of attributes which some events
         # may or may not have.  Aggregating a nonexistent attrib is wasteful,
         # so we check that the attrib or one of its alternates exists.  If
         # one does, then we leave attrib alone because the handler sub will
         # also check alternates.
         if ( !exists $event->{$attrib} ) {
            PTDEBUG && _d("attrib doesn't exist in event:", $attrib);
            my $alt_attrib = $self->{alt_attribs}->{$attrib}->($event);
            PTDEBUG && _d('alt attrib:', $alt_attrib);
            next ATTRIB unless $alt_attrib;
         }

         # The value of the attribute ( $group_by ) may be an arrayref.
         GROUPBY:
         foreach my $val ( ref $group_by ? @$group_by : ($group_by) ) {
            my $class_attrib  = $self->{result_classes}->{$val}->{$attrib} ||= {};
            my $global_attrib = $self->{result_globals}->{$attrib} ||= {};
            my $samples       = $self->{result_samples};
            my $handler = $self->{handlers}->{ $attrib };
            if ( !$handler ) {
               $handler = $self->make_handler(
                  event      => $event,
                  attribute  => $attrib,
                  alternates => $self->{attributes}->{$attrib},
                  worst      => $self->{worst} eq $attrib,
               );
               $self->{handlers}->{$attrib} = $handler;
            }
            next GROUPBY unless $handler;
            $samples->{$val} ||= $event; # Initialize to the first event.
            $handler->($event, $class_attrib, $global_attrib, $samples, $group_by);
         }
      }
   }
   else {
      # After unroll_limit events, unroll the loops.
      $self->_make_unrolled_loops($event);
      # Run unrolled loops here once.  Next time, they'll be ran
      # before this if-else.
      $self->{unrolled_loops}->($self, $event, $group_by);
   }

   return;
}

sub _make_unrolled_loops {
   my ( $self, $event ) = @_;

   my $group_by = $event->{$self->{groupby}};

   # All attributes have handlers, so let's combine them into one faster sub.
   # Start by getting direct handles to the location of each data store and
   # thing that would otherwise be looked up via hash keys.
   my @attrs   = grep { $self->{handlers}->{$_} } keys %{$self->{attributes}};
   my $globs   = $self->{result_globals}; # Global stats for each
   my $samples = $self->{result_samples};

   # Now the tricky part -- must make sure only the desired variables from
   # the outer scope are re-used, and any variables that should have their
   # own scope are declared within the subroutine.
   my @lines = (
      'my ( $self, $event, $group_by ) = @_;',
      'my ($val, $class, $global, $idx);',
      (ref $group_by ? ('foreach my $group_by ( @$group_by ) {') : ()),
      # Create and get each attribute's storage
      'my $temp = $self->{result_classes}->{ $group_by }
         ||= { map { $_ => { } } @attrs };',
      '$samples->{$group_by} ||= $event;', # Always start with the first.
   );
   foreach my $i ( 0 .. $#attrs ) {
      # Access through array indexes, it's faster than hash lookups
      push @lines, (
         '$class  = $temp->{\''  . $attrs[$i] . '\'};',
         '$global = $globs->{\'' . $attrs[$i] . '\'};',
         $self->{unrolled_for}->{$attrs[$i]},
      );
   }
   if ( ref $group_by ) {
      push @lines, '}'; # Close the loop opened above
   }
   @lines = map { s/^/   /gm; $_ } @lines; # Indent for debugging
   unshift @lines, 'sub {';
   push @lines, '}';

   # Make the subroutine.
   my $code = join("\n", @lines);
   PTDEBUG && _d('Unrolled subroutine:', @lines);
   my $sub = eval $code;
   die $EVAL_ERROR if $EVAL_ERROR;
   $self->{unrolled_loops} = $sub;

   return;
}

# Return the aggregated results.
sub results {
   my ( $self ) = @_;
   return {
      classes => $self->{result_classes},
      globals => $self->{result_globals},
      samples => $self->{result_samples},
   };
}

sub set_results {
   my ( $self, $results ) = @_;
   $self->{result_classes} = $results->{classes};
   $self->{result_globals} = $results->{globals};
   $self->{result_samples} = $results->{samples};
   return;
}

sub stats {
   my ( $self ) = @_;
   return {
      classes => $self->{class_metrics},
      globals => $self->{global_metrics},
   };
}

# Return the attributes that this object is tracking, and their data types, as
# a hashref of name => type.
sub attributes {
   my ( $self ) = @_;
   return $self->{type_for};
}

sub set_attribute_types {
   my ( $self, $attrib_types ) = @_;
   $self->{type_for} = $attrib_types;
   return;
}

# Returns the type of the attribute (as decided by the aggregation process,
# which inspects the values).
sub type_for {
   my ( $self, $attrib ) = @_;
   return $self->{type_for}->{$attrib};
}

# Sub: make_handler
#   Make an attribute handler subroutine for <aggregate()>.  Each attribute
#   needs a handler to keep trach of the min and max values, worst sample, etc.
#   Handlers differ depending on the type of attribute (num, bool or string).
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   event     - Event hashref
#   attribute - Attribute name
#
# Optional Arguments:
#   alternates - Arrayref of alternate names for the attribute
#   worst      - Keep a sample of the attribute's worst value (default no)
#
# Returns:
#   A subroutine that can aggregate the attribute.
sub make_handler {
   my ( $self, %args ) = @_;
   my @required_args = qw(event attribute);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $attrib) = @args{@required_args};

   my $val;
   eval { $val= $self->_get_value(%args); };
   if ( $EVAL_ERROR ) {
      PTDEBUG && _d("Cannot make", $attrib, "handler:", $EVAL_ERROR);
      return;
   }
   return unless defined $val; # can't determine type if it's undef

   # Ripped off from Regexp::Common::number and modified.
   my $float_re = qr{[+-]?(?:(?=\d|[.])\d+(?:[.])\d{0,})(?:E[+-]?\d+)?}i;
   my $type = $self->type_for($attrib)           ? $self->type_for($attrib)
            : $attrib =~ m/_crc$/                ? 'string'
            : $val    =~ m/^(?:\d+|$float_re)$/o ? 'num'
            : $val    =~ m/^(?:Yes|No)$/         ? 'bool'
            :                                      'string';
   PTDEBUG && _d('Type for', $attrib, 'is', $type, '(sample:', $val, ')');
   $self->{type_for}->{$attrib} = $type;

   # ########################################################################
   # Begin creating the handler subroutine by writing lines of code.
   # ########################################################################
   my @lines;

   # Some attrib types don't need us to track sum, unq or all--and some do.
   my %track = (
      sum => $type =~ m/num|bool/    ? 1 : 0,  # sum of values
      unq => $type =~ m/bool|string/ ? 1 : 0,  # count of unique values seen
      all => $type eq 'num'          ? 1 : 0,  # all values in bucketed list
   );

   # First, do any transformations to the value if needed.  Right now,
   # it's just bool type attribs that need to be transformed.
   my $trf = ($type eq 'bool') ? q{(($val || '') eq 'Yes') ? 1 : 0}
           :                     undef;
   if ( $trf ) {
      push @lines, q{$val = } . $trf . ';';
   }

   # Handle broken Query_time like 123.124345.8382 (issue 234).
   if ( $attrib eq 'Query_time' ) {
      push @lines, (
         '$val =~ s/^(\d+(?:\.\d+)?).*/$1/;',
         '$event->{\''.$attrib.'\'} = $val;',
      );
   }

   # Make sure the value is constrained to legal limits.  If it's out of
   # bounds, just use the last-seen value for it.
   if ( $type eq 'num' && $self->{attrib_limit} ) {
      push @lines, (
         "if ( \$val > $self->{attrib_limit} ) {",
         '   $val = $class->{last} ||= 0;',
         '}',
         '$class->{last} = $val;',
      );
   }

   # Update values for this attrib in the class and global stores.  We write
   # code for each store.  The placeholder word PLACE is replaced with either
   # $class or $global at the end of the loop.
   my $lt = $type eq 'num' ? '<' : 'lt';
   my $gt = $type eq 'num' ? '>' : 'gt';
   foreach my $place ( qw($class $global) ) {
      my @tmp;  # hold lines until PLACE placeholder is replaced

      # Track count of any and all values seen for this attribute.
      # This is mostly used for class->Query_time->cnt which represents
      # the number of queries in the class because all queries (should)
      # have a Query_time attribute.
      push @tmp, '++PLACE->{cnt};';  # count of all values seen

      # CRC attribs are bucketed in 1k buckets by % 1_000.  We must
      # convert the val early so min and max don't show, e.g. 996791064
      # whereas unq will contain 64 (996791064 % 1_000).
      if ( $attrib =~ m/_crc$/ ) {
         push @tmp, '$val = $val % 1_000;';
      }

      # Track min, max and sum of values.  Min and max for strings is
      # mostly used for timestamps; min ts is earliest and max ts is latest.
      push @tmp, (
         'PLACE->{min} = $val if !defined PLACE->{min} || $val '
            . $lt . ' PLACE->{min};',
      );
      push @tmp, (
         'PLACE->{max} = $val if !defined PLACE->{max} || $val '
         . $gt . ' PLACE->{max};',
      );
      if ( $track{sum} ) {
         push @tmp, 'PLACE->{sum} += $val;';
      }

      # Save all values in a bucketed list.  See bucket_idx() below.
      if ( $track{all} ) {
         push @tmp, (
            'exists PLACE->{all} or PLACE->{all} = {};',
            '++PLACE->{all}->{ EventAggregator::bucket_idx($val) };',
         );
      }

      # Replace PLACE with current variable, $class or $global.
      push @lines, map { s/PLACE/$place/g; $_ } @tmp;
   }

   # We only save unique and worst values for the class, not globally.
   if ( $track{unq} ) {
      push @lines, '++$class->{unq}->{$val}';
   }

   if ( $args{worst} ) {
      my $op = $type eq 'num' ? '>=' : 'ge';
      push @lines, (
         'if ( $val ' . $op . ' ($class->{max} || 0) ) {',
         '   $samples->{$group_by} = $event;',
         '}',
      );
   }

   # Make the core code.  This part is saved for later, as part of an
   # "unrolled" subroutine.
   my @unrolled = (
      # Get $val from primary attrib name.
      "\$val = \$event->{'$attrib'};", 
      
      # Get $val from alternate attrib names.
      ( map  { "\$val = \$event->{'$_'} unless defined \$val;" }
        grep { $_ ne $attrib } @{$args{alternates}}
      ),
      
      # Execute the code lines, if $val is defined.
      'defined $val && do {',
         @lines,
      '};',
   );
   $self->{unrolled_for}->{$attrib} = join("\n", @unrolled);

   # Finally, make a complete subroutine by wrapping the core code inside
   # a "sub { ... }" template.
   my @code = (
      'sub {',
         # Get args and define all variables.
         'my ( $event, $class, $global, $samples, $group_by ) = @_;',
         'my ($val, $idx);',

         # Core code from above.
         $self->{unrolled_for}->{$attrib},

         'return;',
      '}',
   );
   $self->{code_for}->{$attrib} = join("\n", @code);
   PTDEBUG && _d($attrib, 'handler code:', $self->{code_for}->{$attrib});
   my $sub = eval $self->{code_for}->{$attrib};
   if ( $EVAL_ERROR ) {
      die "Failed to compile $attrib handler code: $EVAL_ERROR";
   }

   return $sub;
}

# Sub: bucket_idx
#   Return the bucket number for the given value. Buck numbers are zero-indexed,
#   so although there are 1,000 buckets (NUM_BUCK), 999 is the greatest idx.
# 
#   Notice that this sub is not a class method, so either call it
#   from inside this module like bucket_idx() or outside this module
#   like EventAggregator::bucket_idx().
#
#   The bucketed list works this way: each range of values from MIN_BUCK in
#   increments of BUCK_SIZE (that is 5%) we consider a bucket.  We keep NUM_BUCK
#   buckets.  The upper end of the range is more than 1.5e15 so it should be big
#   enough for almost anything.  The buckets are accessed by log base BUCK_SIZE,
#   so floor(log(N)/log(BUCK_SIZE)).  The smallest bucket's index is -284. We
#   shift all values up 284 so we have values from 0 to 999 that can be used as
#   array indexes.  A value that falls into a bucket simply increments the array
#   entry.  We do NOT use POSIX::floor() because it is too expensive.
#
#   This eliminates the need to keep and sort all values to calculate median,
#   standard deviation, 95th percentile, etc.  So memory usage is bounded by
#   the number of distinct aggregated values, not the number of events.
#
#   TODO: could export this by default to avoid having to specific packge::.
#
# Parameters:
#   $val - Numeric value to bucketize
#
# Returns:
#   Bucket number (0 to NUM_BUCK-1) for the value
sub bucket_idx {
   my ( $val ) = @_;
   return 0 if $val < MIN_BUCK;
   my $idx = int(BASE_OFFSET + log($val)/BASE_LOG);
   return $idx > (NUM_BUCK-1) ? (NUM_BUCK-1) : $idx;
}

# Sub: bucket_value
#   Return the value corresponding to the given bucket.  The value of each
#   bucket is the first value that it covers. So the value of bucket 1 is
#   0.000001000 because it covers [0.000001000, 0.000001050).
#
#   Notice that this sub is not a class method, so either call it
#   from inside this module like bucket_idx() or outside this module
#   like EventAggregator::bucket_value().
#
#   TODO: could export this by default to avoid having to specific packge::.
#
# Parameters:
#   $bucket - Bucket number (0 to NUM_BUCK-1)
#
# Returns:
#   Numeric value corresponding to the bucket
sub bucket_value {
   my ( $bucket ) = @_;
   return 0 if $bucket == 0;
   die "Invalid bucket: $bucket" if $bucket < 0 || $bucket > (NUM_BUCK-1);
   # $bucket - 1 because buckets are shifted up by 1 to handle zero values.
   return (BUCK_SIZE**($bucket-1)) * MIN_BUCK;
}

# Map the 1,000 base 1.05 buckets to 8 base 10 buckets. Returns an array
# of 1,000 buckets, the value of each represents its index in an 8 bucket
# base 10 array. For example: base 10 bucket 0 represents vals (0, 0.000010),
# and base 1.05 buckets 0..47 represent vals (0, 0.000010401). So the first
# 48 elements of the returned array will have 0 as their values. 
# TODO: right now it's hardcoded to buckets of 10, in the future maybe not.
{
   my @buck_tens;
   sub buckets_of {
      return @buck_tens if @buck_tens;

      # To make a more precise map, we first set the starting values for
      # each of the 8 base 10 buckets. 
      my $start_bucket  = 0;
      my @base10_starts = (0);
      map { push @base10_starts, (10**$_)*MIN_BUCK } (1..7);

      # Then find the base 1.05 buckets that correspond to each
      # base 10 bucket. The last value in each bucket's range belongs
      # to the next bucket, so $next_bucket-1 represents the real last
      # base 1.05 bucket in which the base 10 bucket's range falls.
      for my $base10_bucket ( 0..($#base10_starts-1) ) {
         my $next_bucket = bucket_idx( $base10_starts[$base10_bucket+1] );
         PTDEBUG && _d('Base 10 bucket', $base10_bucket, 'maps to',
            'base 1.05 buckets', $start_bucket, '..', $next_bucket-1);
         for my $base1_05_bucket ($start_bucket..($next_bucket-1)) {
            $buck_tens[$base1_05_bucket] = $base10_bucket;
         }
         $start_bucket = $next_bucket;
      }

      # Map all remaining base 1.05 buckets to base 10 bucket 7 which
      # is for vals > 10.
      map { $buck_tens[$_] = 7 } ($start_bucket..(NUM_BUCK-1));

      return @buck_tens;
   }
}

# Calculate 95%, stddev and median for numeric attributes in the
# global and classes stores that have all values (1k buckets).
# Save the metrics in global_metrics and class_metrics.
sub calculate_statistical_metrics {
   my ( $self, %args ) = @_;
   my $classes        = $self->{result_classes};
   my $globals        = $self->{result_globals};
   my $class_metrics  = $self->{class_metrics};
   my $global_metrics = $self->{global_metrics};
   PTDEBUG && _d('Calculating statistical_metrics');
   foreach my $attrib ( keys %$globals ) {
      if ( exists $globals->{$attrib}->{all} ) {
         $global_metrics->{$attrib}
            = $self->_calc_metrics(
               $globals->{$attrib}->{all},
               $globals->{$attrib},
            );
      }

      foreach my $class ( keys %$classes ) {
         if ( exists $classes->{$class}->{$attrib}->{all} ) {
            $class_metrics->{$class}->{$attrib}
               = $self->_calc_metrics(
                  $classes->{$class}->{$attrib}->{all},
                  $classes->{$class}->{$attrib}
               );
         }
      }
   }

   return;
}

# Given a hashref of vals, returns a hashref with the following
# statistical metrics:
#
#    pct_95    => top bucket value in the 95th percentile
#    cutoff    => How many values fall into the 95th percentile
#    stddev    => of all values
#    median    => of all values
#
# The vals hashref represents the buckets as per the above (see the comments
# at the top of this file).  $args should contain cnt, min and max properties.
sub _calc_metrics {
   my ( $self, $vals, $args ) = @_;
   my $statistical_metrics = {
      pct_95    => 0,
      stddev    => 0,
      median    => 0,
      cutoff    => undef,
   };

   # These cases might happen when there is nothing to get from the event, for
   # example, processlist sniffing doesn't gather Rows_examined, so $args won't
   # have {cnt} or other properties.
   return $statistical_metrics
      unless defined $vals && %$vals && $args->{cnt};

   # Return accurate metrics for some cases.
   my $n_vals = $args->{cnt};
   if ( $n_vals == 1 || $args->{max} == $args->{min} ) {
      my $v      = $args->{max} || 0;
      my $bucket = int(6 + ( log($v > 0 ? $v : MIN_BUCK) / log(10)));
      $bucket    = $bucket > 7 ? 7 : $bucket < 0 ? 0 : $bucket;
      return {
         pct_95 => $v,
         stddev => 0,
         median => $v,
         cutoff => $n_vals,
      };
   }
   elsif ( $n_vals == 2 ) {
      foreach my $v ( $args->{min}, $args->{max} ) {
         my $bucket = int(6 + ( log($v && $v > 0 ? $v : MIN_BUCK) / log(10)));
         $bucket = $bucket > 7 ? 7 : $bucket < 0 ? 0 : $bucket;
      }
      my $v      = $args->{max} || 0;
      my $mean = (($args->{min} || 0) + $v) / 2;
      return {
         pct_95 => $v,
         stddev => sqrt((($v - $mean) ** 2) *2),
         median => $mean,
         cutoff => $n_vals,
      };
   }

   # Determine cutoff point for 95% if there are at least 10 vals.  Cutoff
   # serves also for the number of vals left in the 95%.  E.g. with 50 vals
   # the cutoff is 47 which means there are 47 vals: 0..46.  $cutoff is NOT
   # an array index.
   my $cutoff = $n_vals >= 10 ? int ( $n_vals * 0.95 ) : $n_vals;
   $statistical_metrics->{cutoff} = $cutoff;

   # Calculate the standard deviation and median of all values.
   my $total_left = $n_vals;
   my $top_vals   = $n_vals - $cutoff; # vals > 95th
   my $sum_excl   = 0;
   my $sum        = 0;
   my $sumsq      = 0;
   my $mid        = int($n_vals / 2);
   my $median     = 0;
   my $prev       = NUM_BUCK-1; # Used for getting median when $cutoff is odd
   my $bucket_95  = 0; # top bucket in 95th

   PTDEBUG && _d('total vals:', $total_left, 'top vals:', $top_vals, 'mid:', $mid);

   # In ancient times we kept an array of 1k buckets for each numeric
   # attrib.  Each such array cost 32_300 bytes of memory (that's not
   # a typo; yes, it was verified).  But measurements showed that only
   # 1% of the buckets were used on average, meaning 99% of 32_300 was
   # wasted.  Now we store only the used buckets in a hashref which we
   # map to a 1k bucket array for processing, so we don't have to tinker
   # with the delitcate code below.
   # http://code.google.com/p/maatkit/issues/detail?id=866
   my @buckets = map { 0 } (0..NUM_BUCK-1);
   map { $buckets[$_] = $vals->{$_} } keys %$vals;
   $vals = \@buckets;  # repoint vals from given hashref to our array

   BUCKET:
   for my $bucket ( reverse 0..(NUM_BUCK-1) ) {
      my $val = $vals->[$bucket];
      next BUCKET unless $val; 

      $total_left -= $val;
      $sum_excl   += $val;
      $bucket_95   = $bucket if !$bucket_95 && $sum_excl > $top_vals;

      if ( !$median && $total_left <= $mid ) {
         $median = (($cutoff % 2) || ($val > 1)) ? $buck_vals[$bucket]
                 : ($buck_vals[$bucket] + $buck_vals[$prev]) / 2;
      }

      $sum    += $val * $buck_vals[$bucket];
      $sumsq  += $val * ($buck_vals[$bucket]**2);
      $prev   =  $bucket;
   }

   my $var      = $sumsq/$n_vals - ( ($sum/$n_vals) ** 2 );
   my $stddev   = $var > 0 ? sqrt($var) : 0;
   my $maxstdev = (($args->{max} || 0) - ($args->{min} || 0)) / 2;
   $stddev      = $stddev > $maxstdev ? $maxstdev : $stddev;

   PTDEBUG && _d('sum:', $sum, 'sumsq:', $sumsq, 'stddev:', $stddev,
      'median:', $median, 'prev bucket:', $prev,
      'total left:', $total_left, 'sum excl', $sum_excl,
      'bucket 95:', $bucket_95, $buck_vals[$bucket_95]);

   $statistical_metrics->{stddev} = $stddev;
   $statistical_metrics->{pct_95} = $buck_vals[$bucket_95];
   $statistical_metrics->{median} = $median;

   return $statistical_metrics;
}

# Return a hashref of the metrics for some attribute, pre-digested.
# %args is:
#  attrib => the attribute to report on
#  where  => the value of the fingerprint for the attrib
sub metrics {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(attrib where) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $attrib = $args{attrib};
   my $where   = $args{where};

   my $stats      = $self->results();
   my $metrics    = $self->stats();
   my $store      = $stats->{classes}->{$where}->{$attrib};
   my $global_cnt = $stats->{globals}->{$attrib}->{cnt};

   return {
      cnt    => $store->{cnt},
      pct    => $global_cnt && $store->{cnt} ? $store->{cnt} / $global_cnt : 0,
      sum    => $store->{sum},
      min    => $store->{min},
      max    => $store->{max},
      avg    => $store->{sum} && $store->{cnt} ? $store->{sum} / $store->{cnt} : 0,
      median => $metrics->{classes}->{$where}->{$attrib}->{median} || 0,
      pct_95 => $metrics->{classes}->{$where}->{$attrib}->{pct_95} || 0,
      stddev => $metrics->{classes}->{$where}->{$attrib}->{stddev} || 0,
   };
}

# Find the top N or top % event keys, in sorted order, optionally including
# outliers (ol_...) that are notable for some reason.  %args looks like this:
#
#  attrib      order-by attribute (usually Query_time)
#  orderby     order-by aggregate expression (should be numeric, usually sum)
#  total       include events whose summed attribs are <= this number...
#  count       ...or this many events, whichever is less...
#  ol_attrib   ...or events where the 95th percentile of this attribute...
#  ol_limit    ...is greater than this value, AND...
#  ol_freq     ...the event occurred at least this many times.
# The return value is two arrayref.  The first is a list of arrayrefs of the
# chosen (top) events.  Each arrayref is the event key and an explanation of
# why it was included (top|outlier).  The second is a list of the non-top
# event keys.
sub top_events {
   my ( $self, %args ) = @_;
   my $classes = $self->{result_classes};
   my @sorted = reverse sort { # Sorted list of $groupby values
      $classes->{$a}->{$args{attrib}}->{$args{orderby}}
         <=> $classes->{$b}->{$args{attrib}}->{$args{orderby}}
      } grep {
         # Defensive programming
         defined $classes->{$_}->{$args{attrib}}->{$args{orderby}}
      } keys %$classes;
   my @chosen;  # top events
   my @other;   # other events (< top)
   my ($total, $count) = (0, 0);
   foreach my $groupby ( @sorted ) {
      # Events that fall into the top criterion for some reason
      if ( 
         (!$args{total} || $total < $args{total} )
         && ( !$args{count} || $count < $args{count} )
      ) {
         push @chosen, [$groupby, 'top', $count+1];
      }

      # Events that are notable outliers
      elsif ( $args{ol_attrib} && (!$args{ol_freq}
         || $classes->{$groupby}->{$args{ol_attrib}}->{cnt} >= $args{ol_freq})
      ) {
         my $stats = $self->{class_metrics}->{$groupby}->{$args{ol_attrib}};
         if ( ($stats->{pct_95} || 0) >= $args{ol_limit} ) {
            push @chosen, [$groupby, 'outlier', $count+1];
         }
         else {
            push @other, [$groupby, 'misc', $count+1];
         }
      }

      # Events not in the top criterion
      else {
         push @other, [$groupby, 'misc', $count+1];
      }

      $total += $classes->{$groupby}->{$args{attrib}}->{$args{orderby}};
      $count++;
   }
   return \@chosen, \@other;
}

# Adds all new attributes in $event to $self->{attributes}.
sub add_new_attributes {
   my ( $self, $event ) = @_;
   return unless $event;

   map {
      my $attrib = $_;
      $self->{attributes}->{$attrib}  = [$attrib];
      $self->{alt_attribs}->{$attrib} = make_alt_attrib($attrib);
      push @{$self->{all_attribs}}, $attrib;
      PTDEBUG && _d('Added new attribute:', $attrib);
   }
   grep {
      $_ ne $self->{groupby}
      && !exists $self->{attributes}->{$_}
      && !exists $self->{ignore_attribs}->{$_}
   }
   keys %$event;

   return;
}

# Returns an arrayref of all the attributes that were either given
# explicitly to new() or that were auto-detected.
sub get_attributes {
   my ( $self ) = @_;
   return $self->{all_attribs};
}

sub events_processed {
   my ( $self ) = @_;
   return $self->{n_events};
}

sub make_alt_attrib {
   my ( @attribs ) = @_;

   my $attrib = shift @attribs;  # Primary attribute.
   return sub {} unless @attribs;  # No alternates.

   my @lines;
   push @lines, 'sub { my ( $event ) = @_; my $alt_attrib;';
   push @lines, map  {
         "\$alt_attrib = '$_' if !defined \$alt_attrib "
         . "&& exists \$event->{'$_'};"
      } @attribs;
   push @lines, 'return $alt_attrib; }';
   PTDEBUG && _d('alt attrib sub for', $attrib, ':', @lines);
   my $sub = eval join("\n", @lines);
   die if $EVAL_ERROR;
   return $sub;
}

# Merge/add the given arrayref of EventAggregator objects.
# Returns a new EventAggregator obj.
sub merge {
   my ( @ea_objs ) = @_;
   PTDEBUG && _d('Merging', scalar @ea_objs, 'ea');
   return unless scalar @ea_objs;

   # If all the ea don't have the same groupby and worst then adding
   # them will produce a nonsensical result.  (Maybe not if worst
   # differs but certainly if groupby differs).  And while checking this...
   my $ea1   = shift @ea_objs;
   my $r1    = $ea1->results;
   my $worst = $ea1->{worst};  # for merging, finding worst sample

   # ...get all attributes and their types to properly initialize the
   # returned ea obj;
   my %attrib_types = %{ $ea1->attributes() };

   foreach my $ea ( @ea_objs ) {
      die "EventAggregator objects have different groupby: "
         . "$ea1->{groupby} and $ea->{groupby}"
         unless $ea1->{groupby} eq $ea->{groupby};
      die "EventAggregator objects have different worst: "
         . "$ea1->{worst} and $ea->{worst}"
         unless $ea1->{worst} eq $ea->{worst};
      
      my $attrib_types = $ea->attributes();
      map {
         $attrib_types{$_} = $attrib_types->{$_}
            unless exists $attrib_types{$_};
      } keys %$attrib_types;
   }

   # First, deep copy the first ea obj.  Do not shallow copy, do deep copy
   # so the returned ea is truly its own obj and does not point to data
   # structs in one of the given ea.
   my $r_merged = {
      classes => {},
      globals => _deep_copy_attribs($r1->{globals}),
      samples => {},
   };
   map {
      $r_merged->{classes}->{$_}
         = _deep_copy_attribs($r1->{classes}->{$_});

      @{$r_merged->{samples}->{$_}}{keys %{$r1->{samples}->{$_}}}
         = values %{$r1->{samples}->{$_}};
   } keys %{$r1->{classes}};

   # Then, merge/add the other eas.  r1* is the eventual return val.
   # r2* is the current ea being merged/added into r1*.
   for my $i ( 0..$#ea_objs ) {
      PTDEBUG && _d('Merging ea obj', ($i + 1));
      my $r2 = $ea_objs[$i]->results;

      # Descend into each class (e.g. unique query/fingerprint), each
      # attribute (e.g. Query_time, etc.), and then each attribute
      # value (e.g. min, max, etc.).  If either a class or attrib is
      # missing in one of the results, deep copy the extant class/attrib;
      # if both exist, add/merge the results.
      eval {
         CLASS:
         foreach my $class ( keys %{$r2->{classes}} ) {
            my $r1_class = $r_merged->{classes}->{$class};
            my $r2_class = $r2->{classes}->{$class};

            if ( $r1_class && $r2_class ) {
               # Class exists in both results.  Add/merge all their attributes.
               CLASS_ATTRIB:
               foreach my $attrib ( keys %$r2_class ) {
                  PTDEBUG && _d('merge', $attrib);
                  if ( $r1_class->{$attrib} && $r2_class->{$attrib} ) {
                     _add_attrib_vals($r1_class->{$attrib}, $r2_class->{$attrib});
                  }
                  elsif ( !$r1_class->{$attrib} ) {
                  PTDEBUG && _d('copy', $attrib);
                     $r1_class->{$attrib} =
                        _deep_copy_attrib_vals($r2_class->{$attrib})
                  }
               }
            }
            elsif ( !$r1_class ) {
               # Class is missing in r1; deep copy it from r2.
               PTDEBUG && _d('copy class');
               $r_merged->{classes}->{$class} = _deep_copy_attribs($r2_class);
            }

            # Update the worst sample if either the r2 sample is worst than
            # the r1 or there's no such sample in r1.
            my $new_worst_sample;
            if ( $r_merged->{samples}->{$class} && $r2->{samples}->{$class} ) {
               if (   $r2->{samples}->{$class}->{$worst}
                    > $r_merged->{samples}->{$class}->{$worst} ) {
                  $new_worst_sample = $r2->{samples}->{$class}
               }
            }
            elsif ( !$r_merged->{samples}->{$class} ) {
               $new_worst_sample = $r2->{samples}->{$class};
            }
            # Events don't have references to other data structs
            # so we don't have to worry about doing a deep copy.
            if ( $new_worst_sample ) {
               PTDEBUG && _d('New worst sample:', $worst, '=',
                  $new_worst_sample->{$worst}, 'item:', substr($class, 0, 100));
               my %new_sample;
               @new_sample{keys %$new_worst_sample}
                  = values %$new_worst_sample;
               $r_merged->{samples}->{$class} = \%new_sample;
            }
         }
      };
      if ( $EVAL_ERROR ) {
         warn "Error merging class/sample: $EVAL_ERROR";
      }

      # Same as above but for the global attribs/vals.
      eval {
         GLOBAL_ATTRIB:
         PTDEBUG && _d('Merging global attributes');
         foreach my $attrib ( keys %{$r2->{globals}} ) {
            my $r1_global = $r_merged->{globals}->{$attrib};
            my $r2_global = $r2->{globals}->{$attrib};

            if ( $r1_global && $r2_global ) {
               # Global attrib exists in both results.  Add/merge all its values.
               PTDEBUG && _d('merge', $attrib);
               _add_attrib_vals($r1_global, $r2_global);
            }
            elsif ( !$r1_global ) {
               # Global attrib is missing in r1; deep cpoy it from r2 global.
               PTDEBUG && _d('copy', $attrib);
               $r_merged->{globals}->{$attrib}
                  = _deep_copy_attrib_vals($r2_global);
            }
         }
      };
      if ( $EVAL_ERROR ) {
         warn "Error merging globals: $EVAL_ERROR";
      }
   }

   # Create a new EventAggregator obj, initialize it with the summed results,
   # and return it.
   my $ea_merged = new EventAggregator(
      groupby    => $ea1->{groupby},
      worst      => $ea1->{worst},
      attributes => { map { $_=>[$_] } keys %attrib_types },
   );
   $ea_merged->set_results($r_merged);
   $ea_merged->set_attribute_types(\%attrib_types);
   return $ea_merged;
}

# Adds/merges vals2 attrib values into vals1.
sub _add_attrib_vals {
   my ( $vals1, $vals2 ) = @_;

   # Assuming both sets of values are the same attribute (that's the caller
   # responsibility), each should have the same values (min, max, unq, etc.)
   foreach my $val ( keys %$vals1 ) {
      my $val1 = $vals1->{$val};
      my $val2 = $vals2->{$val};

      if ( (!ref $val1) && (!ref $val2) ) {
         # min, max, cnt, sum should never be undef.
         die "undefined $val value" unless defined $val1 && defined $val2;

         # Value is scalar but return unless it's numeric.
         # Only numeric values have "sum".
         my $is_num = exists $vals1->{sum} ? 1 : 0;
         if ( $val eq 'max' ) {
            if ( $is_num ) {
               $vals1->{$val} = $val1 > $val2  ? $val1 : $val2;
            }
            else {
               $vals1->{$val} = $val1 gt $val2 ? $val1 : $val2;
            }
         }
         elsif ( $val eq 'min' ) {
            if ( $is_num ) {
               $vals1->{$val} = $val1 < $val2  ? $val1 : $val2;
            }
            else {
               $vals1->{$val} = $val1 lt $val2 ? $val1 : $val2;
            }
         }
         else {
            $vals1->{$val} += $val2;
         }
      }
      elsif ( (ref $val1 eq 'ARRAY') && (ref $val2 eq 'ARRAY') ) {
         # Value is an arrayref, so it should be 1k buckets.
         # Should never be empty.
         die "Empty $val arrayref" unless @$val1 && @$val2;
         my $n_buckets = (scalar @$val1) - 1;
         for my $i ( 0..$n_buckets ) {
            $vals1->{$val}->[$i] += $val2->[$i];
         }
      }
      elsif ( (ref $val1 eq 'HASH')  && (ref $val2 eq 'HASH')  ) {
         # Value is a hashref, probably for unq string occurences.
         # Should never be empty.
         die "Empty $val hashref" unless %$val1 and %$val2;
         map { $vals1->{$val}->{$_} += $val2->{$_} } keys %$val2;
      }
      else {
         # This shouldn't happen.
         PTDEBUG && _d('vals1:', Dumper($vals1));
         PTDEBUG && _d('vals2:', Dumper($vals2));
         die "$val type mismatch";
      }
   }

   return;
}

# These _deep_copy_* subs only go 1 level deep because, so far,
# no ea data struct has a ref any deeper.
sub _deep_copy_attribs {
   my ( $attribs ) = @_;
   my $copy = {};
   foreach my $attrib ( keys %$attribs ) {
      $copy->{$attrib} = _deep_copy_attrib_vals($attribs->{$attrib});
   }
   return $copy;
}

sub _deep_copy_attrib_vals {
   my ( $vals ) = @_;
   my $copy;
   if ( ref $vals eq 'HASH' ) {
      $copy = {};
      foreach my $val ( keys %$vals ) {
         if ( my $ref_type = ref $val ) {
            if ( $ref_type eq 'ARRAY' ) {
               my $n_elems = (scalar @$val) - 1;
               $copy->{$val} = [ map { undef } ( 0..$n_elems ) ];
               for my $i ( 0..$n_elems ) {
                  $copy->{$val}->[$i] = $vals->{$val}->[$i];
               }
            }
            elsif ( $ref_type eq 'HASH' ) {
               $copy->{$val} = {};
               map { $copy->{$val}->{$_} += $vals->{$val}->{$_} }
                  keys %{$vals->{$val}}
            }
            else {
               die "I don't know how to deep copy a $ref_type reference";
            }
         }
         else {
            $copy->{$val} = $vals->{$val};
         }
      }
   }
   else {
      $copy = $vals;
   }
   return $copy;
}

# Sub: _get_value
#   Get the value of the attribute (or one of its alternatives) from the event.
#   Undef is a valid value.  If the attrib or none of its alternatives exist
#   in the event, then this sub dies.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   event     - Event hashref
#   attribute - Attribute name
#
# Optional Arguments:
#   alternates - Arrayref of alternate attribute names
#
# Returns:
#   Value of attribute in the event, possibly undef
sub _get_value {
   my ( $self, %args ) = @_;
   my ($event, $attrib, $alts) = @args{qw(event attribute alternates)};
   return unless $event && $attrib;

   my $value;
   if ( exists $event->{$attrib} ) {
      $value = $event->{$attrib};
   }
   elsif ( $alts ) {
      my $found_value = 0;
      foreach my $alt_attrib( @$alts ) {
         if ( exists $event->{$alt_attrib} ) {
            $value       = $event->{$alt_attrib};
            $found_value = 1;
            last;
         }
      }
      die "Event does not have attribute $attrib or any of its alternates"
         unless $found_value;
   }
   else {
      die "Event does not have attribute $attrib and there are no alterantes";
   }

   return $value;
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
# End EventAggregator package
# ###########################################################################
