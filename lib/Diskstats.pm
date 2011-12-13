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

BEGIN {
   # This BEGIN block checks if we can use Storable::dclone: If we can't,
   # it clobbers this package's dclone glob (*{ __PACKAGE__ . "::dclone" })
   # with an anonymous function that provides more or less what we need.
   my $have_storable = eval { require Storable };

   if ( $have_storable ) {
      Storable->import(qw(dclone));
   }
   else {
      # An extrenely poor man's dclone.
      require Scalar::Util;

      # Nevermind the prototype. dclone has it, so it's here only it for
      # the sake of completeness.
      *dclone = sub ($) {
         my ($ref) = @_;
         my $reftype = Scalar::Util::reftype($ref) || '';

         if ( $reftype eq ref({}) ) {
            # Only one level of depth. Not worth making it any deeper/recursive, I think.
            return { map { $_ => {%{$ref->{$_}}} } keys %$ref };
         }
         else {
            die "This basic dclone does not support [$reftype]";
         }
      };
   }
}

sub new {
   my ( $class, %args ) = @_;

   my $self = {
      filename           => '/proc/diskstats',
      column_regex       => qr/cnc|rt|mb|busy|prg/,
      device_regex       => qr/(?=)/,
      block_size         => 512,
      out_fh             => \*STDOUT,
      filter_zeroed_rows => 0,
      samples_to_gather  => 0,
      interval           => 0,
      interactive        => 0,
      %args,
      _stats_for         => {},
      _sorted_devs       => [],
      _ts                => {},
      _save_curr_as_prev => 1,    # Internal for now
      _first             => 1,
   };

   return bless $self, $class;
}

sub _ts_common {
   my ($self, $key, $val) = @_;
   if ($val) {
      $self->{_ts}->{$key} = $val;
   }
   return $self->{_ts}->{$key};
}

sub current_ts {
   my ($self, $val) = @_;
   return $self->_ts_common("current", $val);
}

sub previous_ts {
   my ($self, $val) = @_;
   return $self->_ts_common("previous", $val);
}

sub first_ts {
   my ($self, $val) = @_;
   return $self->_ts_common("first", $val);
}

sub filter_zeroed_rows {
   my ($self, $new_val) = @_;
   if ( $new_val ) {
      $self->{filter_zeroed_rows} = $new_val;
   }
   return $self->{filter_zeroed_rows};
}

sub interactive {
   my ($self) = @_;
   return $self->{interactive};
}

sub out_fh {
   my ( $self, $new_fh ) = @_;

   if ( $new_fh && ref($new_fh) && $new_fh->opened ) {
      $self->{out_fh} = $new_fh;
   }
   if ( !$self->{out_fh} || !$self->{out_fh}->opened ) {
      $self->{out_fh} = \*STDOUT;
   }
   return $self->{out_fh};
}

sub column_regex {
   my ( $self, $new_re ) = @_;
   if ($new_re) {
      return $self->{column_regex} = $new_re;
   }
   return $self->{column_regex};
}

sub device_regex {
   my ( $self, $new_re ) = @_;
   if ($new_re) {
      return $self->{device_regex} = $new_re;
   }
   return $self->{device_regex};
}

sub filename {
   my ( $self, $new_filename ) = @_;
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
   my ( $self, $new_dev ) = @_;
   if ( $new_dev && ref($new_dev) eq ref( [] ) ) {
      $self->{_sorted_devs} = $new_dev;
   }
   return @{ $self->{_sorted_devs} };
}

sub add_sorted_devs {
   my ( $self, $new_dev ) = @_;
   if ( !$self->{_seen_devs}->{$new_dev}++ ) {
      push @{ $self->{_sorted_devs} }, $new_dev;
   }
}

# clear_stuff methods. LIke the name says, they clear state stored inside
# the object.

sub clear_state {
   my ($self) = @_;
   $self->{_first} = 1;
   $self->clear_current_stats();
   $self->clear_previous_stats();
   $self->clear_first_stats();
   $self->clear_ts();
   $self->clear_sorted_devs();
}

sub clear_ts {
   my ($self) = @_;
   $self->{_ts} = {};
}

sub clear_sorted_devs {
   my $self = shift;
   $self->{_seen_devs} = {};
   $self->sorted_devs( [] );
}

sub _clear_stats_common {
   my ( $self, $key, @args ) = @_;
   if (@args) {
      for my $dev (@args) {
         $self->{$key}->{$dev} = {};
      }
   }
   else {
      $self->{$key} = {};
   }
}

sub clear_current_stats {
   my ( $self, @args ) = @_;
   $self->_clear_stats_common( "_stats_for", @args );
}

sub clear_previous_stats {
   my ( $self, @args ) = @_;
   $self->_clear_stats_common( "_previous_stats_for", @args );
}

sub clear_first_stats {
   my ( $self, @args ) = @_;
   $self->_clear_stats_common( "_first_stats_for", @args );
}

sub _stats_for_common {
   my ( $self, $dev, $key ) = @_;
   $self->{$key} ||= {};
   if ($dev) {
      return $self->{$key}->{$dev};
   }
   return $self->{$key};
}

sub stats_for {
   my ( $self, $dev ) = @_;
   $self->_stats_for_common( $dev, '_stats_for' );
}

sub previous_stats_for {
   my ( $self, $dev ) = @_;
   $self->_stats_for_common( $dev, '_previous_stats_for' );
}

sub first_stats_for {
   my ( $self, $dev ) = @_;
   $self->_stats_for_common( $dev, '_first_stats_for' );
}

sub has_stats {
   my ($self) = @_;

   return $self->stats_for
     && scalar grep 1, @{ $self->stats_for }{ $self->sorted_devs };
}

sub trim {
   my ($c) = @_;
   $c =~ s/^\s+//;
   $c =~ s/\s+$//;
   return $c;
}

sub col_ok {
   my ( $self, $column ) = @_;
   my $regex = $self->column_regex;
   return $column =~ $regex || trim($column) =~ $regex;
}

sub dev_ok {
   my ( $self, $device ) = @_;
   my $regex = $self->device_regex;
   return $device =~ $regex;
}

my @columns_in_order = (
   # Column        # Format   # Key name
   [ "   rd_s" => "%7.1f",   "reads_sec", ],
   [ "rd_avkb" => "%7.1f",   "avg_read_sz", ],
   [ "rd_mb_s" => "%7.1f",   "mbytes_read_sec", ],
   [ "rd_mrg"  => "%5.0f%%", "read_merge_pct", ],
   [ "rd_cnc"  => "%6.1f",   "read_conc", ],
   [ "  rd_rt" => "%7.1f",   "read_rtime", ],
   [ "   wr_s" => "%7.1f",   "writes_sec", ],
   [ "wr_avkb" => "%7.1f",   "avg_write_sz", ],
   [ "wr_mb_s" => "%7.1f",   "mbytes_written_sec", ],
   [ "wr_mrg"  => "%5.0f%%", "write_merge_pct", ],
   [ "wr_cnc"  => "%6.1f",   "write_conc", ],
   [ "  wr_rt" => "%7.1f",   "write_rtime", ],
   [ "busy"    => "%3.0f%%", "busy", ],
   [ "in_prg"  => "%6d",     "in_progress", ],
);

{

   my %format_for = ( map { ( $_->[0] => $_->[1] ) } @columns_in_order, );

   sub _format_for {
      my ( $self, $col ) = @_;
      return $format_for{$col};
   }

}

{

   my %column_to_key = ( map { ( $_->[0] => $_->[2] ) } @columns_in_order, );

   sub _column_to_key {
      my ( $self, $col ) = @_;
      return $column_to_key{$col};
   }

}

sub design_print_formats {
   my ( $self,       %args )    = @_;
   my ( $dev_length, $columns ) = @args{qw( max_device_length columns )};
   $dev_length ||= max 6, map length, $self->sorted_devs;
   my ( $header, $format );

   # For each device, print out the following: The timestamp offset and
   # device name.
   $header = $format = qq{%5s %-${dev_length}s };

   if ( !$columns ) {
      @$columns = grep { $self->col_ok($_) } map { $_->[0] } @columns_in_order;
   }
   elsif ( !ref($columns) || ref($columns) ne ref([]) ) {
      die "The columns argument to design_print_formats should be an arrayref";
   }

   $header .= join " ", @$columns;
   $format .= join " ", map $self->_format_for($_), @$columns;

   return ( $header, $format, $columns );
}

sub parse_diskstats_line {
   my ( $self, $line, $block_size ) = @_;
   my @keys = qw(
     reads  reads_merged  read_sectors      ms_spent_reading
     writes writes_merged written_sectors   ms_spent_writing
     ios_in_progress      ms_spent_doing_io ms_weighted
   );
   my ( $dev, %dev_stats );

   if ( ( @dev_stats{qw( major minor )}, $dev, @dev_stats{@keys} ) =
         $line =~ /^
            # Disk format
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
               \s*$/x
     )
   {
      $dev_stats{read_bytes} = $dev_stats{read_sectors} * $block_size;
      $dev_stats{written_bytes} =
        $dev_stats{written_sectors} * $block_size;
      $dev_stats{read_kbs}    = $dev_stats{read_bytes} / 1024;
      $dev_stats{written_kbs} = $dev_stats{written_bytes} / 1024;
      $dev_stats{ttreq} += $dev_stats{reads} + $dev_stats{writes};
      $dev_stats{ttbyt} += $dev_stats{read_bytes} + $dev_stats{written_bytes};

      return ( $dev, \%dev_stats );
   }
   elsif ((@dev_stats{qw( major minor )}, $dev, @dev_stats{ qw( reads read_sectors writes written_sectors ) }) = $line =~ /^
            # Partition format
               \s*   (\d+)    # major
               \s+   (\d+)    # minor
               \s+   (.+?)    # Device name
               \s+   (\d+)    # # of reads issued
               \s+   (\d+)    # # of sectors read
               \s+   (\d+)    # # of writes issued
               \s+   (\d+)    # # of sectors written
               \s*$/x) {
      for my $key ( @keys ) {
         $dev_stats{$key} ||= 0;
      }
      # Copypaste from above, abstract?
      $dev_stats{read_bytes} = $dev_stats{read_sectors} * $block_size;
      $dev_stats{written_bytes} =
        $dev_stats{written_sectors} * $block_size;
      $dev_stats{read_kbs}    = $dev_stats{read_bytes} / 1024;
      $dev_stats{written_kbs} = $dev_stats{written_bytes} / 1024;
      $dev_stats{ttreq} += $dev_stats{reads} + $dev_stats{writes};
      $dev_stats{ttbyt} += $dev_stats{read_bytes} + $dev_stats{written_bytes};

      return ( $dev, \%dev_stats );
   }
   else {
      return;
   }
}

sub _save_current_as_previous {
   my ( $self, $curr_hashref ) = @_;

   if ( $self->{_save_curr_as_prev} ) {
      $self->{_previous_stats_for} = $curr_hashref;
      for my $dev (keys %$curr_hashref) {
         $self->{_previous_stats_for}->{$dev}->{sum_ios_in_progress} +=
            $curr_hashref->{$dev}->{ios_in_progress};
      }
      $self->previous_ts($self->current_ts());
   }

   return;
}

sub _save_current_as_first {
   my ($self, $curr_hashref) = @_;

   if ( $self->{_first} ) {
      $self->{_first_stats_for} = $curr_hashref;
      $self->first_ts($self->current_ts());
      $self->{_first} = undef;
   }
}

sub _save_stats {
   my ( $self, $hashref ) = @_;
   $self->{_stats_for} = $hashref;
}

# Method: parse_from()
#   Parses data from one of the sources.
#
# Parameters:
#   %args - Arguments
#
# Optional Arguments:
#   filehandle       - Reads data from a filehandle by calling readline() on it.
#   data             - Reads data one line at a time.
#   filename         - Opens a filehandle to the file and reads it one line at a time.
#   sample_callback  - Called each time a sample is processed, passed the latest timestamp.
#

sub parse_from {
   my ( $self, %args ) = @_;

   my $lines_read = $args{filehandle}
      ? $self->parse_from_filehandle( @args{qw( filehandle sample_callback )} ) :
      $args{data}
      ? $self->parse_from_data( @args{qw( data sample_callback )} )             :
      $self->parse_from_filename( @args{qw( filename sample_callback )} );
   return $lines_read;
}

sub parse_from_filename {
   my ( $self, $filename, $sample_callback ) = @_;

   $filename ||= $self->filename;

   open my $fh, "<", $filename
     or die "Couldn't open ", $filename, ": $OS_ERROR";
   my $lines_read = $self->parse_from_filehandle( $fh, $sample_callback );
   close($fh) or die "Couldn't close: $OS_ERROR";

   return $lines_read;
}
# Method: parse_from_filehandle()
#   Parses data received from using readline() on the filehandle. This is
#   particularly useful, as you could pass in a filehandle to a pipe, or
#   a tied filehandle, or a PerlIO::Scalar handle. Or your normal
#   run of the mill filehandle.
#
# Parameters:
#   $filehandle      - 
#   sample_callback  - Called each time a sample is processed, passed the latest timestamp.
#

sub parse_from_filehandle {
   my ( $self, $filehandle, $sample_callback ) = @_;
   return $self->_load( $filehandle, $sample_callback );;
}

sub parse_from_data {
   my ( $self, $data, $sample_callback ) = @_;

   open my $fh, "<", \$data
     or die "Couldn't open scalar as filehandle: $OS_ERROR";
   my $lines_read = $self->parse_from_filehandle( $fh, $sample_callback );
   close($fh);

   return $lines_read;
}

# Method: parse_from()
#   Reads from the filehandle, either saving the data as needed if dealing
#   with a diskstats-formatted line, or if it finds a TS line and has a
#   callback, defering to that.

sub _load {
   my ( $self, $fh, $sample_callback ) = @_;
   my $lines_read = 0;
   my $block_size = $self->block_size;

   my $new_cur = {};

   while ( my $line = <$fh> ) {
      if ( my ( $dev, $dev_stats ) = $self->parse_diskstats_line($line, $block_size) ) {
         $new_cur->{$dev} = $dev_stats;
         $self->add_sorted_devs($dev);
      }
      elsif ( my ($ts) = $line =~ /TS\s+([0-9]+(?:\.[0-9]+)?)/ ) {
         if ( %{$new_cur} ) {
            $self->_save_current_as_previous( $self->stats_for() );
            $self->_save_stats($new_cur);
            $self->current_ts($ts);
            $self->_save_current_as_first( dclone($self->stats_for) );
            $new_cur = {};
         }
         # XXX TODO Ugly hack for interactive mode
         my $ret = 0;
         if ($sample_callback) {
            $ret = $self->$sample_callback($ts);
         }
         $lines_read = $NR;
         last if $ret;
      }
      else {
         chomp($line);
         die "Line [$line] isn't in the diskstats format";
      }
   }

   if ( %{$new_cur} ) {
      #$self->_save_stats($new_cur);
      $self->_save_current_as_first( dclone($self->stats_for) );
   }
   return $lines_read;
}

sub _calc_read_stats {
   my ( $self, $delta_for, $elapsed, $devs_in_group ) = @_;

   my %read_stats = (
      reads_sec       => $delta_for->{reads} / $elapsed,
      read_requests   => $delta_for->{reads_merged} + $delta_for->{reads},
      mbytes_read_sec => $delta_for->{read_kbs} / $elapsed / 1024,
      read_conc       => $delta_for->{ms_spent_reading} /
                           $elapsed / 1000 / $devs_in_group,
   );

   if ( $delta_for->{reads} > 0 ) {
      $read_stats{read_rtime} =
        $delta_for->{ms_spent_reading} / $delta_for->{reads};
      $read_stats{avg_read_sz} =
        $delta_for->{read_kbs} / $delta_for->{reads};
   }
   else {
      $read_stats{read_rtime}  = 0;
      $read_stats{avg_read_sz} = 0;
   }

   $read_stats{read_merge_pct} =
     $read_stats{read_requests} > 0
     ? 100 * $delta_for->{reads_merged} / $read_stats{read_requests}
     : 0;

   return %read_stats;
}

sub _calc_write_stats {
   my ( $self, $delta_for, $elapsed, $devs_in_group ) = @_;

   my %write_stats = (
      writes_sec     => $delta_for->{writes} / $elapsed,
      write_requests => $delta_for->{writes_merged} + $delta_for->{writes},

      mbytes_written_sec  => $delta_for->{written_kbs} / $elapsed / 1024,
      write_conc         => $delta_for->{ms_spent_writing} /
        $elapsed / 1000 /
        $devs_in_group,
   );

   if ( $delta_for->{writes} > 0 ) {
      $write_stats{write_rtime} =
        $delta_for->{ms_spent_writing} / $delta_for->{writes};
      $write_stats{avg_write_sz} =
        $delta_for->{written_kbs} / $delta_for->{writes};
   }
   else {
      $write_stats{write_rtime}  = 0;
      $write_stats{avg_write_sz} = 0;
   }

   $write_stats{write_merge_pct} =
     $write_stats{write_requests} > 0
     ? 100 * $delta_for->{writes_merged} / $write_stats{write_requests}
     : 0;

   return %write_stats;
}


# Compute the numbers for reads and writes together, the things for
# which we do not have separate statistics.
# Busy is what iostat calls %util.  This is the percent of
# wall-clock time during which the device has I/O happening.

sub _calc_misc_stats {
   my ( $self, $delta_for, $elapsed, $devs_in_group, $stats ) = @_;
   my %extra_stats;

   $extra_stats{busy} =
      100 *
      $delta_for->{ms_spent_doing_io} /
      ( 1000 * $elapsed * $devs_in_group );

   my $number_of_ios   = $stats->{write_requests} + $stats->{read_requests};
   my $total_ms_spent_on_io = $delta_for->{ms_spent_reading} + $delta_for->{ms_spent_writing};

   $extra_stats{qtime} = $number_of_ios ? $total_ms_spent_on_io / $number_of_ios : 0;
   $extra_stats{stime} = $number_of_ios ? $delta_for->{ms_spent_doing_io} / $number_of_ios : 0;

   $extra_stats{line_ts} = $self->compute_line_ts(
      first_ts   => $self->first_ts(),
      current_ts => $self->current_ts(),
   );

   return %extra_stats;
}

sub _calc_delta_for {
   my ( $self, $current, $against ) = @_;
   return {
      map { ( $_ => $current->{$_} - $against->{$_} ) }
        qw(
         reads reads_merged read_sectors ms_spent_reading
         writes writes_merged written_sectors ms_spent_writing
         read_kbs written_kbs
         ms_spent_doing_io ms_weighted
        )
   };
}

sub _calc_stats_for_deltas {
   my ( $self, $elapsed ) = @_;
   my @end_stats;

   for my $dev ( grep { $self->dev_ok($_) && $self->stats_for($_) } $self->sorted_devs ) {
      my $curr    = $self->stats_for($dev);
      my $against = $self->delta_against($dev);

      my $delta_for = $self->_calc_delta_for( $curr, $against );

      my $in_progress = $curr->{"ios_in_progress"};
      my $tot_in_progress = $against->{"sum_ios_in_progress"} || 0;

      my $devs_in_group = $self->compute_devs_in_group;

      # Compute the per-second stats for reads, writes, and overall.
      my %stats = (
         $self->_calc_read_stats( $delta_for, $elapsed, $devs_in_group ),
         $self->_calc_write_stats( $delta_for, $elapsed, $devs_in_group ),
         in_progress =>
           $self->compute_in_progress( $in_progress, $tot_in_progress ),
      );

      my %extras = $self->_calc_misc_stats( $delta_for, $elapsed, $devs_in_group, \%stats );
      while ( my ($k, $v) = each %extras ) {
         $stats{$k} = $v;
      }

      $stats{dev} = $dev;

      push @end_stats, \%stats;
   }
   return @end_stats;
}

sub _calc_deltas {
   my ( $self, $callback ) = @_;

   my $elapsed = $self->current_ts() - $self->delta_against_ts();
   die "Time elapsed is [$elapsed]" unless $elapsed;

   return $self->_calc_stats_for_deltas($elapsed);
}

sub print_header {
   my ($self, $header, @args) = @_;
   printf { $self->out_fh } $header . "\n", @args;
}

sub print_rest {
   my ($self, $format, $cols, $stat) = @_;
   if ( $self->filter_zeroed_rows ) {
      return unless grep $_, @{$stat}{ @$cols };
   }
   printf { $self->out_fh } $format . "\n",
           @{$stat}{ qw( line_ts dev ), @$cols };
}

sub print_deltas {
   my ( $self, %args ) = @_;
   my ( $header, $format, $cols ) = $self->design_print_formats(
      max_device_length => $args{max_device_length},
      columns           => $args{columns},
   );

   return unless $self->delta_against_ts();

   @$cols = map { $self->_column_to_key($_) } @$cols;
   my ( $header_cb, $rest_cb ) = @args{qw( header_cb rest_cb )};

   if ( $header_cb ) {
      $self->$header_cb( $header, "#ts", "device" );
   }
   else {
      $self->print_header( $header, "#ts", "device" );
   }

   for my $stat ( $self->_calc_deltas() ) {
      if ($rest_cb) {
         $self->$rest_cb( $format, $cols, $stat );
      }
      else {
         $self->print_rest( $format, $cols, $stat );
      }
   }
}

sub compute_line_ts {
   my ( $self, %args ) = @_;
   return $args{first_ts} > 0
     ? sprintf( "%5.1f", $args{current_ts} - $args{first_ts} )
     : sprintf( "%5.1f", 0 );
}

sub compute_in_progress {
   my ( $self, $in_progress, $tot_in_progress ) = @_;
   return $in_progress;
}

sub compute_devs_in_group {
   return 1;
}

sub delta_against {
   die 'You must override delta_against() in a subclass';
}

sub delta_against_ts {
   die 'You must override delta_against_ts() in a subclass';
}

sub group_by {
   die 'You must override group_by() in a subclass';
}

1;

}
# ###########################################################################
# End Diskstats package
# ###########################################################################
