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
# EventTimeline package
# ###########################################################################
{
# Package: EventTimeline
# EventTimeline aggregates events that are adjacent to each other.
package EventTimeline;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

Transformers->import(qw(parse_timestamp secs_to_time unix_timestamp));

use constant KEY     => 0;
use constant CNT     => 1;
use constant ATT     => 2;

# The best way to see how to use this is to look at the .t file.
#
# %args is a hash containing:
# groupby      An arrayref of names of properties to group/aggregate by.
# attributes   An arrayref of names of properties to aggregate.
#              Aggregation keeps the min, max and sum if it's a numeric
#              attribute.
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(groupby attributes) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my %is_groupby = map { $_ => 1 } @{$args{groupby}};

   return bless {
      groupby    => $args{groupby},
      attributes => [ grep { !$is_groupby{$_} } @{$args{attributes}} ],
      results    => [],
   }, $class;
}

# Reset the aggregated data, but not anything the code has learned about
# incoming data.
sub reset_aggregated_data {
   my ( $self ) = @_;
   $self->{results} = [];
}

# Aggregate an event hashref's properties.
sub aggregate {
   my ( $self, $event ) = @_;
   my $handler = $self->{handler};
   if ( !$handler ) {
      $handler = $self->make_handler($event);
      $self->{handler} = $handler;
   }
   return unless $handler;
   $handler->($event);
}

# Return the aggregated results.
sub results {
   my ( $self ) = @_;
   return $self->{results};
}

# Make subroutines that do things with events.
#
# $event:  a sample event
#
# Return value:
# a subroutine with this signature:
#    my ( $event ) = @_;
sub make_handler {
   my ( $self, $event ) = @_;

   # Ripped off from Regexp::Common::number.
   my $float_re = qr{[+-]?(?:(?=\d|[.])\d*(?:[.])\d{0,})?(?:[E](?:[+-]?\d+)|)}i;
   my @lines; # lines of code for the subroutine

   foreach my $attrib ( @{$self->{attributes}} ) {
      my ($val) = $event->{$attrib};
      next unless defined $val; # Can't decide type if it's undef.

      my $type = $val  =~ m/^(?:\d+|$float_re)$/o ? 'num'
               : $val  =~ m/^(?:Yes|No)$/         ? 'bool'
               :                                    'string';
      PTDEBUG && _d('Type for', $attrib, 'is', $type, '(sample:', $val, ')');
      $self->{type_for}->{$attrib} = $type;

      push @lines, (
         "\$val = \$event->{$attrib};",
         'defined $val && do {',
         "# type: $type",
         "\$store = \$last->[ATT]->{$attrib} ||= {};",
      );

      if ( $type eq 'bool' ) {
         push @lines, q{$val = $val eq 'Yes' ? 1 : 0;};
         $type = 'num';
      }
      my $op   = $type eq 'num' ? '<' : 'lt';
      push @lines, (
         '$store->{min} = $val if !defined $store->{min} || $val '
            . $op . ' $store->{min};',
      );
      $op = ($type eq 'num') ? '>' : 'gt';
      push @lines, (
         '$store->{max} = $val if !defined $store->{max} || $val '
            . $op . ' $store->{max};',
      );
      if ( $type eq 'num' ) {
         push @lines, '$store->{sum} += $val;';
      }
      push @lines, '};';
   }

   # Build a subroutine with the code.
   unshift @lines, (
      'sub {',
      'my ( $event ) = @_;',
      'my ($val, $last, $store);', # NOTE: define all variables here
      '$last = $results->[-1];',
      'if ( !$last || '
         . join(' || ',
            map { "\$last->[KEY]->[$_] ne (\$event->{$self->{groupby}->[$_]} || 0)" }
                (0 .. @{$self->{groupby}} -1))
         . ' ) {',
      '  $last = [['
         . join(', ',
            map { "(\$event->{$self->{groupby}->[$_]} || 0)" }
                (0 .. @{$self->{groupby}} -1))
         . '], 0, {} ];',
      '  push @$results, $last;',
      '}',
      '++$last->[CNT];',
   );
   push @lines, '}';
   my $results = $self->{results}; # Referred to by the eval
   my $code = join("\n", @lines);
   $self->{code} = $code;

   PTDEBUG && _d('Timeline handler:', $code);
   my $sub = eval $code;
   die if $EVAL_ERROR;
   return $sub;
}

sub report {
   my ( $self, $results, $callback ) = @_;
   $callback->("# " . ('#' x 72) . "\n");
   $callback->("# " . join(',', @{$self->{groupby}}) . " report\n");
   $callback->("# " . ('#' x 72) . "\n");
   foreach my $res ( @$results ) {
      my $t;
      my @vals;
      if ( ($t = $res->[ATT]->{ts}) && $t->{min} ) {
         my $min = parse_timestamp($t->{min});
         push @vals, $min;
         if ( $t->{max} && $t->{max} gt $t->{min} ) {
            my $max  = parse_timestamp($t->{max});
            my $diff = secs_to_time(unix_timestamp($max) - unix_timestamp($min));
            push @vals, $diff;
         }
         else {
            push @vals, '0:00';
         }
      }
      else {
         push @vals, ('', '');
      }
      $callback->(sprintf("# %19s %7s %3d %s\n", @vals, $res->[CNT], $res->[KEY]->[0]));
   }
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
# End EventTimeline package
# ###########################################################################
