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
# Diskstats package
# ###########################################################################
{
# Package: Diskstats
# 

package Diskstats;

use warnings;
use strict;
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use IO::Handle;
use List::Util qw( max first );

sub new {
    my ( $class, %args ) = @_;
 
    my $self = {
        filename     => '/proc/diskstats',
        column_regex => qr/cnc|rt|mb|busy|prg/,
        device_regex => qr/(?=)/,
        block_size   => 512,
        stats_for    => {},
        out_fh       => \*STDOUT,
        %args,
        _sorted_devs  => [],
        _save_curr_as_prev => 1, # Internal for now
        _first             => 1,
    };

    return bless $self, $class;
}

sub out_fh {
   my ($self, $new_fh) = @_;

   if ($new_fh && ref($new_fh) && $new_fh->opened) {
      $self->{out_fh} = $new_fh;
   }
   if (!$self->{out_fh} || !$self->{out_fh}->opened) {
      $self->{out_fh} = \*STDOUT;
   }
   return $self->{out_fh};
}

sub column_regex {
   my ($self, $new_re) = @_;
   if ($new_re) {
      return $self->{column_regex} = $new_re;
   }
   return $self->{device_regex};
}

sub device_regex {
   my ($self, $new_re) = @_;
   if ($new_re) {
      return $self->{device_regex} = $new_re;
   }
   return $self->{device_regex};
}

sub filename {
   my ($self, $new_filename) = @_;
   if ($new_filename) {
      return $self->{filename} = $new_filename;
   }
   return $self->{filename} || '/proc/diskstats';
}

sub block_size {
   my $self = shift;
   return $self->{block_size};
}

sub sorted_devs {
   my ($self, $new_dev) = @_;
   if ( $new_dev && !first { $new_dev eq $_ } @{$self->{_sorted_devs}} ) {
      push @{$self->{_sorted_devs}}, $new_dev;
   }
   return $self->{_sorted_devs};
}

sub clear_state {
   my ($self) = @_;
   $self->{_first} = 1;
   $self->clear_current_stats();
   $self->clear_previous_stats();
   $self->clear_first_stats();
   $self->clear_sorted_devs();
}

sub clear_sorted_devs {
   my $self = shift;
   $self->{_sorted_devs} = [];
}

sub _clear_stats_common {
   my ($self, $key, @args) = @_;
   if (@args) {
      for my $dev (@_) {
         $self->{$key}->{$dev} = {};
      }
   }
   else {
      $self->{$key} = {};
   }
}

sub clear_current_stats {
   my ($self, @args) = @_;
   $self->_clear_stats_common("stats_for", @args);
}

sub clear_previous_stats {
   my ($self, @args) = @_;
   $self->_clear_stats_common("previous_stats_for", @args);
}

sub clear_first_stats {
   my ($self, @args) = @_;
   $self->_clear_stats_common("first_stats_for", @args);
}

sub _stats_for_common {
   my ($self, $dev, $key) = @_;
   $self->{$key} ||= {};
   if ($dev) {
      return $self->{$key}->{$dev};
   }
   return $self->{$key};   
}

sub stats_for {
   my ($self, $dev) = @_;
   $self->_stats_for_common($dev, 'stats_for');
}

sub previous_stats_for {
   my ($self, $dev) = @_;
   $self->_stats_for_common($dev, 'previous_stats_for');
}

sub first_stats_for {
   my ($self, $dev) = @_;
   $self->_stats_for_common($dev, 'first_stats_for');
}

sub has_stats {
   my ($self) = @_;
   # XXX TODO Greh. The stats_for hash has a bunch of stuff that shouldn't
   # be public. Implementation detail showing through, FIX.
   return $self->stats_for
            && scalar grep 1, @{ $self->stats_for }{ @{$self->sorted_devs} };
}

my @columns_in_order = (
   # Colum        # Format   # Key name
   [ "   rd_s" => "%7.1f",   "reads_sec",          ],
   [ "rd_avkb" => "%7.1f",   "avg_read_sz",        ],
   [ "rd_mb_s" => "%7.1f",   "mbytes_read_sec",    ],
   [ "rd_mrg"  => "%5.0f%%", "read_merge_pct",     ],
   [ "rd_cnc"  => "%6.1f",   "read_conc",          ],
   [ "  rd_rt" => "%7.1f",   "read_rtime",         ],
   [ "   wr_s" => "%7.1f",   "writes_sec",         ],
   [ "wr_avkb" => "%7.1f",   "avg_write_sz",       ],
   [ "wr_mb_s" => "%7.1f",   "mbytes_written_sec", ],
   [ "wr_mrg"  => "%5.0f%%", "write_merge_pct",    ],
   [ "wr_cnc"  => "%6.1f",   "write_conc",         ],
   [ "  wr_rt" => "%7.1f",   "write_rtime",        ],
   [ "busy"    => "%3.0f%%", "busy",               ],
   [ "in_prg"  => "%6d",     "in_progress",        ],
);

my %format_for = (
   map { ( $_->[0] => $_->[1] ) } @columns_in_order,
);

{

my %column_to_key = (
   map { ( $_->[0] => $_->[2] ) } @columns_in_order,
);

sub _column_to_key {
   my ($self, $col) = @_;
   return $column_to_key{$col};
}

}

sub design_print_formats {
   my $self = shift;
   my ($dev_length, @columns) = @_;
   my ($header, $format);
   # For each device, print out the following: The timestamp offset and
   # device name.
   $header = $format = qq{%5s %-${dev_length}s };

   if ( !@columns ) {
      @columns = grep { $self->col_ok($_) } map { $_->[0] } @columns_in_order;
   }

   $header .= join " ", @columns;
   $format .= join " ", @format_for{@columns};

   return ($header, $format, \@columns);
}

sub trim {
   my ($c) = @_;
   $c =~ s/^\s+//;
   $c =~ s/\s+$//;
   return $c;
}

sub col_ok {
   my ($self, $column) = @_;
   my $regex      =  $self->column_regex;
   return $column =~ $regex || trim($column) =~ $regex;
}

sub dev_ok {
   my ($self, $device) = @_;
   my $regex    = $self->device_regex;
   return $device =~ $regex;
}

sub parse_diskstats_line {
    my ($self, $line) = @_;
    my @keys = qw(
                    reads  reads_merged  read_sectors      ms_spent_reading
                    writes writes_merged written_sectors   ms_spent_writing
                    ios_in_progress      ms_spent_doing_io ms_weighted
                );
    my ($dev, %dev_stats);

    if ((@dev_stats{qw( major minor )}, $dev, @dev_stats{@keys}) = $line =~ /^
               \s*   (\d+)    # major
               \s+   (\d+)    # minor
               \s+   (.+?)    # Device name
               \s+   (\d+)    # # of reads issued
               \s+   (\d+)    # # of reads merged
               \s+   (\d+)    # # of sectors read
               \s+   (\d+)    # # of milliseconds spent reading
               \s+   (\d+)    # # of writes completed
               \s+   (\d+)    # # of writes merged
               \s+   (\d+)    # # of sectors written
               \s+   (\d+)    # # of milliseconds spent writing
               \s+   (\d+)    # # of IOs currently in progress
               \s+   (\d+)    # # of milliseconds spent doing IOs
               \s+   (\d+)    # weighted # of milliseconds spent doing IOs
               \s*$/x)
    {
         $dev_stats{read_bytes}    = $dev_stats{read_sectors}    * $self->block_size;
         $dev_stats{written_bytes} = $dev_stats{written_sectors} * $self->block_size;
         $dev_stats{read_kbs}      = $dev_stats{read_bytes}      / 1024;
         $dev_stats{written_kbs}   = $dev_stats{written_bytes}   / 1024;
         $dev_stats{ttreq}        += $dev_stats{reads}      + $dev_stats{writes};
         $dev_stats{ttbyt}        += $dev_stats{read_bytes} + $dev_stats{written_bytes};

         return ($dev, \%dev_stats);
    }
    else {
        return;
    }
}

sub _save_current_as_previous {
   my ($self, $dev) = @_;
   if ( $self->{_save_curr_as_prev} ) {
      if ( $dev ) {
         my $curr = $self->stats_for($dev);
         return unless $curr;
         while ( my ($k, $v) = each %$curr ) {
            $self->{previous_stats_for}->{$dev}{$k} = $v;
         }
         $self->previous_stats_for($dev)->{sum_ios_in_progress} += $curr->{ios_in_progress};
         $self->previous_stats_for->{_ts}  = $self->stats_for->{_ts};
      }
      else {
         for my $dev ( grep { $_ ne '_ts' } keys %{$self->stats_for} ) {
            $self->previous_stats_for->{$dev} = \%{$self->stats_for->{$dev}};
         }
         $self->previous_stats_for->{_ts} = $self->stats_for->{_ts};
      }
    }
}

sub _save_current_as_first {
   my ($self) = @_;
   if ( $self->{_first} ) {
      for my $dev ( grep { $_ ne '_ts' } keys %{$self->stats_for} ) {
         $self->first_stats_for->{$dev} = \%{$self->stats_for->{$dev}};
      }
      $self->first_stats_for->{_ts} = $self->stats_for->{_ts};
      $self->{_first} = undef;
   }
}

sub parse_from {
   my ($self, %args) = @_;

   if ($args{filehandle}) {
      $self->parse_from_filehandle(@args{ qw( filehandle ts_callback ) });
   }
   elsif ($args{data}) {
      open my $fh, "<", \$args{data}
         or die "Couldn't open scalar as filehandle: $OS_ERROR";
      $self->parse_from_filehandle($fh, $args{ts_callback});
      close($fh);
   }
   else {
      $self->parse_from_filename(@args{ qw( filename ts_callback ) });
   }
   return;
}

sub parse_from_filename {
   my ($self, $filename, $ts_callback) = @_;

   $filename ||= $self->filename;

   open my $fh, "<", $filename
      or die "Couldn't open ", $filename, ": $OS_ERROR";

   $self->parse_from_filehandle($fh, $ts_callback);

   close($fh) or die "Couldn't close: $OS_ERROR";
   return;
}

sub parse_from_filehandle {
   my ($self, $filehandle, $ts_callback) = @_;
   $self->_load($filehandle, $ts_callback);
   return;
}

# Reads from the filehandle, either saving the data as needed if dealing
# with a diskstats-formatted line, or if it finds a TS line and has a
# callback, defering to that.

sub _load {
   my ($self, $fh, $ts_callback) = @_;

   while (my $line = <$fh>) {
      if ( my ($dev, $dev_stats) = $self->parse_diskstats_line($line) ) {
         $self->_save_current_as_previous($dev);
         $self->clear_current_stats($dev);

         @{$self->stats_for($dev)}{ keys %$dev_stats } = values %$dev_stats;
         $self->sorted_devs($dev);
      }
      elsif ( my ($ts) = $line =~ /TS\s+([0-9]+(?:\.[0-9]+)?)/ ) {
         if ( $self->has_stats() ) {
            $self->stats_for->{_ts} = $ts;
            $self->_save_current_as_first;
         }
         if ( $ts_callback ) {
            $self->$ts_callback($ts);
         }
      }
      else {
         chomp($line);
         die "Line [$line] isn't in the diskstats format";
      }
   }
   $self->_save_current_as_first;   
   return;
}

sub _calc_read_stats {
   my $self = shift;
   my ($delta_for, $elapsed, $devs_in_group) = @_;

   my %read_stats = (
      reads_sec       => $delta_for->{reads} / $elapsed,
      read_requests   => $delta_for->{reads_merged} + $delta_for->{reads},
#      mbytes_read_sec => $delta_for->{read_kbs} / $elapsed / 2048,
      mbytes_read_sec => $delta_for->{read_sectors} / $elapsed / 2048,
      read_conc       => $delta_for->{ms_spent_reading} / $elapsed / 1000 / $devs_in_group,
   );

   if ( $delta_for->{reads} > 0 ) {
      $read_stats{read_rtime}   = $delta_for->{ms_spent_reading} / $delta_for->{reads};
      $read_stats{avg_read_sz}  = $delta_for->{read_sectors} / $delta_for->{reads};
   }
   else {
      $read_stats{read_rtime}   = 0;
      $read_stats{avg_read_sz}  = 0;
   }

   $read_stats{read_merge_pct}  = $read_stats{read_requests} > 0
                        ? 100 * $delta_for->{reads_merged} / $read_stats{read_requests}
                        : 0;

   return %read_stats;
}

sub _calc_write_stats {
   my $self = shift;
   my ($delta_for, $elapsed, $devs_in_group) = @_;

   my %write_stats = (
      writes_sec          => $delta_for->{writes} / $elapsed,
      write_requests      => $delta_for->{writes_merged} + $delta_for->{writes},
#      mbytes_written_sec  => $delta_for->{written_kbs} / $elapsed / 2048,
      mbytes_written_sec  => $delta_for->{written_sectors} / $elapsed / 2048,
      write_conc          => $delta_for->{ms_spent_writing} / $elapsed / 1000 / $devs_in_group,
   );

   if ( $delta_for->{writes} > 0 ) {
      $write_stats{write_rtime}  = $delta_for->{ms_spent_writing} / $delta_for->{writes};
      $write_stats{avg_write_sz} = $delta_for->{written_sectors} / $delta_for->{writes};
   }
   else {
      $write_stats{write_rtime}  = 0;
      $write_stats{avg_write_sz} = 0;
   }

   $write_stats{write_merge_pct} = $write_stats{write_requests} > 0 ? 100 * $delta_for->{writes_merged} / $write_stats{write_requests} : 0;

   return %write_stats;
}

sub _calc_delta_for {
   my ($self, $current, $against) = @_;
   return {
            map { ($_ => $current->{$_} - $against->{$_}) }
              qw(
                  reads reads_merged read_sectors ms_spent_reading
                  writes writes_merged written_sectors ms_spent_writing
                  read_kbs written_kbs
                  ms_spent_doing_io ms_weighted
                )
          };
}

sub _calc_deltas {
   my $self = shift;
   my ($callback) = @_;

   my $elapsed = $self->stats_for->{_ts} - $self->delta_against->{_ts};
   die "Time elapsed is 0" unless $elapsed;
   my @end_stats;

   for my $dev ( grep { $self->dev_ok($_) } @{$self->sorted_devs} ) {
      my $curr    = $self->stats_for($dev);
      my $against = $self->delta_against($dev);

      my $delta_for = $self->_calc_delta_for($curr, $against);

      my $in_progress       = $curr->{"ios_in_progress"};
      my $tot_in_progress   = $against->{"sum_ios_in_progress"} || 0;

      my $devs_in_group     = $self->compute_devs_in_group;

      # Compute the per-second stats for reads, writes, and overall.
      my %stats = (
         $self->_calc_read_stats($delta_for, $elapsed, $devs_in_group),
         $self->_calc_write_stats($delta_for, $elapsed, $devs_in_group),
         in_progress => $self->compute_in_progress($in_progress, $tot_in_progress),
      );
   
      # Compute the numbers for reads and writes together, the things for
      # which we do not have separate statistics.
      # Busy is what iostat calls %util.  This is the percent of
      # wall-clock time during which the device has I/O happening.
      $stats{busy} = 100 * $delta_for->{ms_spent_doing_io} / (1000 * $elapsed * $devs_in_group);
      $stats{line_ts} = $self->compute_line_ts(
                           first_ts   => $self->first_stats_for->{_ts},
                           current_ts => $self->stats_for->{_ts},
                        );

      $stats{dev} = $dev;

      if ($callback) {
         $self->$callback( \%stats );
      }
      push @end_stats, \%stats;
   }
   return @end_stats;
}

sub print_deltas {
   my ($self, %args) = @_;
   my $longest_dev = $args{dev_length} || max 6, map length, @{$self->sorted_devs};
   my ($header, $format, $cols) = $self->design_print_formats($longest_dev);

   @$cols = map { $self->_column_to_key($_) } @$cols;

   my ($header_cb, $rest_cb) = @args{ qw( header_cb rest_cb ) };

   return unless $self->delta_against->{_ts};

   if ($header_cb) {
      $self->$header_cb($header, "#ts", "device");
   }
   else {
      printf { $self->out_fh } $header."\n", "#ts", "device";
   }

   if ($rest_cb) {
      $self->_calc_deltas( sub { shift->$rest_cb($format, $cols, shift) } );
   }
   else {
      for my $stat ( $self->_calc_deltas() ) {
         printf { $self->out_fh } $format."\n", @{$stat}{ qw( line_ts dev ), @$cols };
      }
   }

}

sub compute_line_ts {
   ... # $self->first_stats_for->{"ts"} > 0 ? sprintf("%5.1f", $curr->{ts} - $self->first_stats_for->{ts}) : sprintf("%5.1f", 0);
}

sub compute_in_progress {
   ...
}

sub compute_devs_in_group {
   1;
}

sub delta_against {
   ... # previous_stats_for or first_stats_for
}

1;
}
# ###########################################################################
# End Diskstats package
# ###########################################################################
