# This program is copyright 2011 Percona Ireland Ltd.
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
# This package implements most of the logic in the old shell pt-diskstats;
# it parses data from /proc/diskstats, calculcates deltas, and prints those.

package Diskstats;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use IO::Handle;
use List::Util qw( max first );

use ReadKeyMini qw( GetTerminalSize );

my $max_lines;
BEGIN {
   (undef, $max_lines)       = GetTerminalSize();
   $max_lines              ||= 24;
   $Diskstats::printed_lines = $max_lines;
}

my $diskstat_colno_for;
BEGIN {
   $diskstat_colno_for = {
      # Columns of a /proc/diskstats line.
      MAJOR               => 0,
      MINOR               => 1,
      DEVICE              => 2,
      READS               => 3,
      READS_MERGED        => 4,
      READ_SECTORS        => 5,
      MS_SPENT_READING    => 6,
      WRITES              => 7,
      WRITES_MERGED       => 8,
      WRITTEN_SECTORS     => 9,
      MS_SPENT_WRITING    => 10,
      IOS_IN_PROGRESS     => 11,
      MS_SPENT_DOING_IO   => 12,
      MS_WEIGHTED         => 13,
      # Values we compute from the preceding columns.
      READ_KBS            => 14,
      WRITTEN_KBS         => 15,
      IOS_REQUESTED       => 16,
      IOS_IN_BYTES        => 17,
      SUM_IOS_IN_PROGRESS => 18,
   };
   require constant;
   constant->import($diskstat_colno_for);
}

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($o) = @args{@required_args};

   # Regex patterns.
   my $columns = $o->get('columns-regex');
   my $devices = $o->get('devices-regex');

   # Header magic and so on.
   my $headers = $o->get('headers');

   my $self = {
      # Defaults
      filename           => '/proc/diskstats',
      block_size         => 512,
      show_inactive      => $o->get('show-inactive'),
      sample_time        => $o->get('sample-time') || 0,
      automatic_headers  => $headers->{'scroll'},
      space_samples      => $headers->{'group'},
      show_timestamps    => $o->get('show-timestamps'),
      columns_regex      => qr/$columns/,
      devices_regex      => $devices ? qr/$devices/ : undef,
      interactive        => 0,
      force_header       => 1,

      %args,

      delta_cols         => [  # Calc deltas for these cols, must be uppercase
         qw(
            READS
            READS_MERGED
            READ_SECTORS
            MS_SPENT_READING
            WRITES
            WRITES_MERGED
            WRITTEN_SECTORS
            MS_SPENT_WRITING
            READ_KBS
            WRITTEN_KBS
            MS_SPENT_DOING_IO
            MS_WEIGHTED
            READ_KBS
            WRITTEN_KBS
            IOS_REQUESTED
            IOS_IN_BYTES
            IOS_IN_PROGRESS
         )
      ],
      _stats_for         => {},
      _ordered_devs      => [],
      _active_devices    => {},
      _ts                => {},
      _first_stats_for   => {},
      _nochange_skips    => [],

      _length_ts_column  => 5,

      # Internal for now, but might need APIfying.
      _save_curr_as_prev => 1,
   };

   if ( $self->{show_timestamps} ) {
      $self->{_length_ts_column} = 8;
   }

   $Diskstats::last_was_header = 0;

   return bless $self, $class;
}

# The next lot are accessors, plus some convenience functions.

sub first_ts_line {
   my ($self) = @_;
   return $self->{_ts}->{first}->{line};
}

sub set_first_ts_line {
   my ($self, $new_val) = @_;
   return $self->{_ts}->{first}->{line} = $new_val;
}

sub prev_ts_line {
   my ($self) = @_;
   return $self->{_ts}->{prev}->{line};
}

sub set_prev_ts_line {
   my ($self, $new_val) = @_;
   return $self->{_ts}->{prev}->{line} = $new_val;
}

sub curr_ts_line {
   my ($self) = @_;
   return $self->{_ts}->{curr}->{line};
}

sub set_curr_ts_line {
   my ($self, $new_val) = @_;
   return $self->{_ts}->{curr}->{line} = $new_val;
}

sub show_line_between_samples {
   my ($self) = @_;
   return $self->{space_samples};
}

sub set_show_line_between_samples {
   my ($self, $new_val) = @_;
   return $self->{space_samples} = $new_val;
}

sub show_timestamps {
   my ($self) = @_;
   return $self->{show_timestamps};
}

sub set_show_timestamps {
   my ($self, $new_val) = @_;
   return $self->{show_timestamps} = $new_val;
}

sub active_device {
   my ( $self, $dev ) = @_;
   return $self->{_active_devices}->{$dev};
}

sub set_active_device {
   my ($self, $dev, $val) = @_;
   return $self->{_active_devices}->{$dev} = $val;
}

sub clear_active_devices {
   my ( $self ) = @_;
   return $self->{_active_devices} = {};
}

sub automatic_headers {
   my ($self) = @_;
   return $self->{automatic_headers};
}

sub set_automatic_headers {
   my ($self, $new_val) = @_;
   return $self->{automatic_headers} = $new_val;
}

sub curr_ts {
   my ($self) = @_;
   return $self->{_ts}->{curr}->{ts} || 0;
}

sub set_curr_ts {
   my ($self, $val) = @_;
   $self->{_ts}->{curr}->{ts} = $val || 0;
}

sub prev_ts {
   my ($self) = @_;
   return $self->{_ts}->{prev}->{ts} || 0;
}

sub set_prev_ts {
   my ($self, $val) = @_;
   $self->{_ts}->{prev}->{ts} = $val || 0;
}

sub first_ts {
   my ($self) = @_;
   return $self->{_ts}->{first}->{ts} || 0;
}

sub set_first_ts {
   my ($self, $val) = @_;
   $self->{_ts}->{first}->{ts} = $val || 0;
}

sub show_inactive {
   my ($self) = @_;
   return $self->{show_inactive};
}

sub set_show_inactive {
   my ($self, $new_val) = @_;
   $self->{show_inactive} = $new_val;
}

sub sample_time {
   my ($self) = @_;
   return $self->{sample_time};
}

sub set_sample_time {
   my ($self, $new_val) = @_;
   if (defined($new_val)) {
      $self->{sample_time} = $new_val;
   }
}

sub interactive {
   my ($self) = @_;
   return $self->{interactive};
}

sub set_interactive {
   my ($self, $new_val) = @_;
   if (defined($new_val)) {
      $self->{interactive} = $new_val;
   }
}

sub columns_regex {
   my ( $self ) = @_;
   return $self->{columns_regex};
}

sub set_columns_regex {
   my ( $self, $new_re ) = @_;
   return $self->{columns_regex} = $new_re;
}

sub devices_regex {
   my ( $self ) = @_;
   return $self->{devices_regex};
}

sub set_devices_regex {
   my ( $self, $new_re ) = @_;
   return $self->{devices_regex} = $new_re;
}

sub filename {
   my ( $self ) = @_;
   return $self->{filename};
}

sub set_filename {
   my ( $self, $new_filename ) = @_;
   if ( $new_filename ) {
      return $self->{filename} = $new_filename;
   }
}

sub block_size {
   my ( $self ) = @_;
   return $self->{block_size};
}

# Returns a list of devices seen. You may pass an arrayref argument to
# replace the internal list, but consider using clear_ordered_devs and
# add_ordered_dev instead.

sub ordered_devs {
   my ( $self, $replacement_list ) = @_;
   if ( $replacement_list ) {
      $self->{_ordered_devs} = $replacement_list;
   }
   return @{ $self->{_ordered_devs} };
}

sub add_ordered_dev {
   my ( $self, $new_dev ) = @_;
   if ( !$self->{_seen_devs}->{$new_dev}++ ) {
      push @{ $self->{_ordered_devs} }, $new_dev;
   }
   return;
}

# clear_stuff methods. Like the name says, they clear state stored inside
# the object.

sub force_header {
   my ($self) = @_;
   return $self->{force_header};
}

sub set_force_header {
   my ($self, $new_val) = @_;
   return $self->{force_header} = $new_val;
}

sub clear_state {
   my ($self, %args) = @_;
   $self->set_force_header(1);
   $self->clear_curr_stats();
   if ( $args{force} || !$self->interactive() ) {
      $self->clear_first_stats();
      $self->clear_prev_stats();
   }
   $self->clear_ts();
   $self->clear_ordered_devs();
}

sub clear_ts {
   my ($self) = @_;
   undef($_->{ts}) for @{ $self->{_ts} }{ qw( curr prev first ) };
}

sub clear_ordered_devs {
   my ($self) = @_;
   $self->{_seen_devs} = {};
   $self->ordered_devs( [] );
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

sub clear_curr_stats {
   my ( $self, @args ) = @_;

# TODO: Is this a bug?
   if ( $self->has_stats() ) {
      $self->_save_curr_as_prev();
   }

   $self->_clear_stats_common( "_stats_for", @args );
}

sub clear_prev_stats {
   my ( $self, @args ) = @_;
   $self->_clear_stats_common( "_prev_stats_for", @args );
}

sub clear_first_stats {
   my ( $self, @args ) = @_;
   $self->_clear_stats_common( "_first_stats_for", @args );
}

sub stats_for {
   my ( $self, $dev ) = @_;
   $self->{_stats_for} ||= {};
   if ($dev) {
      return $self->{_stats_for}->{$dev};
   }
   return $self->{_stats_for};
}

sub prev_stats_for {
   my ( $self, $dev ) = @_;
   $self->{_prev_stats_for} ||= {};
   if ($dev) {
      return $self->{_prev_stats_for}->{$dev};
   }
   return $self->{_prev_stats_for};
}

sub first_stats_for {
   my ( $self, $dev ) = @_;
   $self->{_first_stats_for} ||= {};
   if ($dev) {
      return $self->{_first_stats_for}->{$dev};
   }
   return $self->{_first_stats_for};
}

sub has_stats {
   my ($self) = @_;
   my $stats  = $self->stats_for;

   for my $key ( keys %$stats ) {
      return 1 if $stats->{$key} && @{ $stats->{$key} }
   }

   return;
}

sub _save_curr_as_prev {
   my ( $self, $curr ) = @_;

   if ( $self->{_save_curr_as_prev} ) {
      $self->{_prev_stats_for} = $curr;
      for my $dev (keys %$curr) {
         $self->{_prev_stats_for}->{$dev}->[SUM_IOS_IN_PROGRESS] +=
            $curr->{$dev}->[IOS_IN_PROGRESS];
      }
      $self->set_prev_ts($self->curr_ts());
   }

   return;
}

sub _save_curr_as_first {
   my ($self, $curr) = @_;

   if ( !%{$self->{_first_stats_for}} ) {
      $self->{_first_stats_for} = {
         map { $_ => [@{$curr->{$_}}] } keys %$curr
      };
      $self->set_first_ts($self->curr_ts());
   }
}

sub trim {
   my ($c) = @_;
   $c =~ s/^\s+//;
   $c =~ s/\s+$//;
   return $c;
}

sub col_ok {
   my ( $self, $column ) = @_;
   my $regex = $self->columns_regex();
   return ($column =~ $regex) || (trim($column) =~ $regex);
}

our @columns_in_order = (
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
   [ "   io_s" => "%7.1f",   "s_spent_doing_io", ],
   [ " qtime"  => "%6.1f",   "qtime", ],
   [ "stime"   => "%5.1f",   "stime", ],
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

# Method: design_print_formats()
#   What says on the label. Returns three things: the format for the header
#   and the data, and an arrayref of the columns used to make it.
#
# Parameters:
#   %args - Arguments
#
# Optional Arguments:
#   columns             - An arrayref with column names. If absent,
#                         uses ->col_ok to decide which columns to use.
#   max_device_length   - How much space to leave for device names.
#                         Defaults to 6.
#

sub design_print_formats {
   my ( $self,       %args )    = @_;
   my ( $dev_length, $columns ) = @args{qw( max_device_length columns )};
   $dev_length ||= max 6, map length, $self->ordered_devs();
   my ( $header, $format );

   # For each device, print out the following: The timestamp offset and
   # device name.
   $header = $format = qq{%+*s %-${dev_length}s };

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

   # Since we assume that device names can't have spaces.
   my @dev_stats = split ' ', $line;
   return unless @dev_stats == 14;

   my $read_bytes    = $dev_stats[READ_SECTORS]    * $block_size;
   my $written_bytes = $dev_stats[WRITTEN_SECTORS] * $block_size;

   $dev_stats[READ_KBS]      = $read_bytes    / 1024;
   $dev_stats[WRITTEN_KBS]   = $written_bytes / 1024;
   $dev_stats[IOS_IN_BYTES]  = $read_bytes + $written_bytes;
   $dev_stats[IOS_REQUESTED]
      = $dev_stats[READS] + $dev_stats[WRITES]
      + $dev_stats[READS_MERGED] +$dev_stats[WRITES_MERGED];

   return $dev_stats[DEVICE], \@dev_stats;
}

# Method: parse_from()
#   Parses data from one of the sources.
#
# Parameters:
#   %args - Arguments
#
# Optional Arguments:
#   filehandle       - Reads data from a filehandle.
#   data             - A normal scalar, opened as a scalar filehandle,
#                      after which it behaves like the above argument.
#   filename         - Opens a filehandle to the file and reads it one
#                      line at a time.
#   sample_callback  - Called each time a sample is processed, passed
#                      the latest timestamp.
#

sub parse_from {
   my ( $self, %args ) = @_;

   my $lines_read;
   if ($args{filehandle}) {
      $lines_read = $self->_parse_from_filehandle(
                        @args{qw( filehandle sample_callback )}
                     );
   }
   elsif ( $args{data} ) {
      open( my $fh, "<", ref($args{data}) ? $args{data} : \$args{data} )
         or die "Couldn't parse data: $OS_ERROR";
      $lines_read = $self->_parse_from_filehandle(
                        $fh, $args{sample_callback}
                     );
      close $fh or warn "Cannot close: $OS_ERROR";
   }
   else {
      my $filename = $args{filename} || $self->filename();
   
      open my $fh, "<", $filename
         or die "Cannot parse $filename: $OS_ERROR";
      $lines_read = $self->_parse_from_filehandle(
                        $fh, $args{sample_callback}
                     );
      close $fh or warn "Cannot close: $OS_ERROR";
   }

   return $lines_read;
}

# Method: _parse_from_filehandle()
#   Parses data received from using readline() on the filehandle. This is
#   particularly useful, as you could pass in a filehandle to a pipe, or
#   a tied filehandle, or a PerlIO::Scalar handle. Or your normal
#   run of the mill filehandle.
#
# Parameters:
#   filehandle       - 
#   sample_callback  - Called each time a sample is processed, passed
#                      the latest timestamp.
#

sub _parse_from_filehandle {
   my ( $self, $filehandle, $sample_callback ) = @_;
   return $self->_parse_and_load_diskstats( $filehandle, $sample_callback );
}

# Method: _parse_and_load_diskstats()
#   !!!!INTERNAL!!!!!
#   Reads from the filehandle, either saving the data as needed if dealing
#   with a diskstats-formatted line, or if it finds a TS line and has a
#   callback, defering to that.

sub _parse_and_load_diskstats {
   my ( $self, $fh, $sample_callback ) = @_;
   my $block_size = $self->block_size();
   my $current_ts = 0;
   my $new_cur    = {};
   my $last_ts_line;

   while ( my $line = <$fh> ) {
      # The order of parsing here is intentionally backwards -- While the
      # timestamp line will always happen first, it's actually the rarest
      # thing to find -- Once ever couple dozen lines or so.
      # This matters, because on a normal run, checking for the TS line
      # first ends up in some ~10000 ultimately useless calls to the
      # regular expression engine, and thus a noticeable slowdown;
      # Something in the order of 2 seconds or so, per file.
      if ( my ( $dev, $dev_stats )
               = $self->parse_diskstats_line($line, $block_size) )
      {
         $new_cur->{$dev} = $dev_stats;
         $self->add_ordered_dev($dev);
      }
      elsif ( my ($new_ts) = $line =~ /^TS\s+([0-9]+(?:\.[0-9]+)?)/ ) {
         PTDEBUG && _d("Timestamp:", $line);
         if ( $current_ts && %$new_cur ) {
            $self->_handle_ts_line($current_ts, $new_cur, $line, $sample_callback);
            $new_cur = {};
         }
         $current_ts = $new_ts;
         $last_ts_line = $line;
      }
      else {
         PTDEBUG && _d("Ignoring unknown diskstats line:", $line);
      }
   }

   if ( $current_ts && %{$new_cur} ) {
      $self->_handle_ts_line($current_ts, $new_cur, $last_ts_line, $sample_callback);
      $new_cur = {};
   }

   return $INPUT_LINE_NUMBER;
}

sub _handle_ts_line {
   my ($self, $current_ts, $new_cur, $line, $sample_callback) = @_;

   $self->set_first_ts_line( $line ) unless $self->first_ts_line();
   $self->set_prev_ts_line( $self->curr_ts_line() );
   $self->set_curr_ts_line( $line );

   $self->_save_curr_as_prev( $self->stats_for() );
   $self->{_stats_for} = $new_cur;
   $self->set_curr_ts($current_ts);
   $self->_save_curr_as_first( $new_cur );

   if ($sample_callback) {
      $self->$sample_callback($current_ts);
   }
   return;
}

sub _calc_read_stats {
   my ( $self, %args ) = @_;

   my @required_args = qw( delta_for elapsed devs_in_group );
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($delta_for, $elapsed, $devs_in_group) = @args{ @required_args };

   my %read_stats = (
      reads_sec       => $delta_for->{reads} / $elapsed,
      read_requests   => $delta_for->{reads_merged} + $delta_for->{reads},
      mbytes_read_sec => $delta_for->{read_kbs} / $elapsed / 1024,
      read_conc       => $delta_for->{ms_spent_reading} /
                           $elapsed / 1000 / $devs_in_group,
   );

   if ( $delta_for->{reads} > 0 ) {
      $read_stats{read_rtime} =
        $delta_for->{ms_spent_reading} / $read_stats{read_requests};
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
   my ( $self, %args ) = @_;

   my @required_args = qw( delta_for elapsed devs_in_group );
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($delta_for, $elapsed, $devs_in_group) = @args{ @required_args };

   my %write_stats = (
      writes_sec         => $delta_for->{writes} / $elapsed,
      write_requests     => $delta_for->{writes_merged} + $delta_for->{writes},
      mbytes_written_sec => $delta_for->{written_kbs} / $elapsed / 1024,
      write_conc         => $delta_for->{ms_spent_writing} /
        $elapsed / 1000 /
        $devs_in_group,
   );

   if ( $delta_for->{writes} > 0 ) {
      $write_stats{write_rtime} =
        $delta_for->{ms_spent_writing} / $write_stats{write_requests};
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

sub _calc_misc_stats {
   my ( $self, %args ) = @_;

   my @required_args = qw( delta_for elapsed devs_in_group stats );
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($delta_for, $elapsed, $devs_in_group, $stats) = @args{ @required_args };
   my %extra_stats;

   # Busy is what iostat calls %util.  This is the percent of
   # wall-clock time during which the device has I/O happening.
   $extra_stats{busy}
      = 100
      * $delta_for->{ms_spent_doing_io}
      / ( 1000 * $elapsed * $devs_in_group ); # Highlighting failure: /

   my $number_of_ios        = $delta_for->{ios_requested}; # sum(delta[field1, 2, 5, 6])
   my $total_ms_spent_on_io = $delta_for->{ms_spent_reading}
                            + $delta_for->{ms_spent_writing};

   if ( $number_of_ios ) {
      my $average_ios = $number_of_ios + $delta_for->{ios_in_progress};
      if ( $average_ios ) {
         $extra_stats{qtime} =  $delta_for->{ms_weighted} / $average_ios
                           - $delta_for->{ms_spent_doing_io} / $number_of_ios;
      }
      else {
         PTDEBUG && _d("IOS_IN_PROGRESS is [", $delta_for->{ios_in_progress},
                       "], and the number of ios is [", $number_of_ios,
                       "], going to use 0 as qtime.");
         $extra_stats{qtime} = 0;
      }
      $extra_stats{stime}
         = $delta_for->{ms_spent_doing_io} / $number_of_ios;
   }
   else {
      $extra_stats{qtime} = 0;
      $extra_stats{stime} = 0;
   }

   $extra_stats{s_spent_doing_io}
      = $stats->{reads_sec} + $stats->{writes_sec};

   $extra_stats{line_ts} = $self->compute_line_ts(
      first_ts   => $self->first_ts(),
      curr_ts    => $self->curr_ts(),
   );

   return %extra_stats;
}

sub _calc_delta_for {
   my ( $self, $curr, $against ) = @_;
   my %deltas;
   foreach my $col ( @{$self->{delta_cols}} ) {
      my $colno = $diskstat_colno_for->{$col};
      $deltas{lc $col} = ($curr->[$colno] || 0) - ($against->[$colno] || 0);
   }
   return \%deltas;
}

sub _print_device_if {
   # This method decides whenever a device should be printed.
   # As per Baron's mail, it tries this:
   # * Print all devices specified by --devices-regex, regardless
   #   of whether they've changed
   # Otherwise,
   # * Print all devices when --show-inactive is given
   # Otherwise,
   # * Print all devices whose line in /proc/diskstats is different
   #   from the first-ever observed sample

   my ($self, $dev ) = @_;
   my $dev_re = $self->devices_regex();

   if ( $dev_re ) {
      # device_regex was set explicitly, either through --devices-regex,
      # or by using the d option in interactive mode, and not leaving
      # it blank
      $self->_mark_if_active($dev);
      return $dev if $dev =~ $dev_re;
   }
   else {   
      if ( $self->active_device($dev) ) {
         # If --show-interactive is enabled, or we've seen
         # the device be active at least once.
         return $dev;
      }
      elsif ( $self->show_inactive() ) {
         $self->_mark_if_active($dev);
         return $dev;
      }
      else {
         return $dev if $self->_mark_if_active($dev);
      }
   }
   # Not active, add it to the list of skips for debugging.
   push @{$self->{_nochange_skips}}, $dev;
   return;
}

sub _mark_if_active {
   my ($self, $dev) = @_;

   return $dev if $self->active_device($dev);

   my $curr         = $self->stats_for($dev);
   my $first        = $self->first_stats_for($dev);

   return unless $curr && $first;

 # read 'any' instead of 'first'
   if ( first { $curr->[$_] != $first->[$_] } READS..IOS_IN_BYTES ) {
      # It's different from the first one. Mark as active and return.
      $self->set_active_device($dev, 1);
      return $dev;
   }
   return;
}

sub _calc_stats_for_deltas {
   my ( $self, $elapsed ) = @_;
   my @end_stats;
   my @devices = $self->ordered_devs();

   my $devs_in_group = $self->compute_devs_in_group();

   # Read "For each device that passes the dev_ok regex, and we have stats for"
   foreach my $dev ( grep { $self->_print_device_if($_) } @devices ) {
      my $curr    = $self->stats_for($dev);
      my $against = $self->delta_against($dev);

      next unless $curr && $against;

      my $delta_for       = $self->_calc_delta_for( $curr, $against );
      my $in_progress     = $curr->[IOS_IN_PROGRESS];
      my $tot_in_progress = $against->[SUM_IOS_IN_PROGRESS] || 0;

      # Compute the per-second stats for reads, writes, and overall.
      my %stats = (
         $self->_calc_read_stats(
            delta_for     => $delta_for,
            elapsed       => $elapsed,
            devs_in_group => $devs_in_group,
         ),
         $self->_calc_write_stats(
            delta_for     => $delta_for,
            elapsed       => $elapsed,
            devs_in_group => $devs_in_group,
         ),
         in_progress =>
           $self->compute_in_progress( $in_progress, $tot_in_progress ),
      );

      my %extras = $self->_calc_misc_stats(
         delta_for     => $delta_for,
         elapsed       => $elapsed,
         devs_in_group => $devs_in_group,
         stats         => \%stats,
      );

      @stats{ keys %extras } = values %extras;

      $stats{dev} = $dev;

      push @end_stats, \%stats;
   }
   if ( @{$self->{_nochange_skips}} ) {
      my $devs = join ", ", @{$self->{_nochange_skips}};
      PTDEBUG && _d("Skipping [$devs], haven't changed from the first sample");
      $self->{_nochange_skips} = [];
   }
   return @end_stats;
}

sub _calc_deltas {
   my ( $self ) = @_;

   my $elapsed = $self->curr_ts() - $self->delta_against_ts();
   die "Time between samples should be > 0, is [$elapsed]" if $elapsed <= 0;

   return $self->_calc_stats_for_deltas($elapsed);
}

# Always print a header, disgreard the value of $self->force_header()
sub force_print_header {
   my ($self, @args) = @_;
   my $orig = $self->force_header();
   $self->set_force_header(1);
   $self->print_header(@args);
   $self->set_force_header($orig);
   return;
}

sub print_header {
   my ($self, $header, @args) = @_;
   if ( $self->force_header() ) {
      printf $header . "\n", $self->{_length_ts_column}, @args;
      $Diskstats::printed_lines--;
      $Diskstats::printed_lines ||= $max_lines;
      $Diskstats::last_was_header = 1;
   }
   return;
}

sub print_rows {
   my ($self, $format, $cols, $stat) = @_;

   printf $format . "\n", $self->{_length_ts_column}, @{ $stat }{ qw( line_ts dev ), @$cols };
   $Diskstats::printed_lines--;
   $Diskstats::last_was_header = 0;
}

sub print_deltas {
   my ( $self, %args ) = @_;

   my ( $header, $format, $cols ) = $self->design_print_formats(
      # Not required args, because design_print_formats picks sane defaults.
      max_device_length => $args{max_device_length},
      columns           => $args{columns},
   );

   return unless $self->delta_against_ts();

   @$cols = map { $self->_column_to_key($_) } @$cols;

   my $header_method = $args{header_callback} || "print_header";
   my $rows_method   = $args{rows_callback}   || "print_rows";

   my @stats = $self->_calc_deltas();

   $Diskstats::printed_lines = $max_lines
      unless defined $Diskstats::printed_lines;

   if ( $self->{space_samples} && @stats && @stats > 1
         && !$Diskstats::last_was_header ) {
      # Print an empty line before the rows if we have more
      # than one thing to print.
      print "\n";
      $Diskstats::printed_lines--;
   }

   if ( $self->automatic_headers() && $Diskstats::printed_lines <= @stats ) {
      $self->force_print_header( $header, "#ts", "device" );
   }
   else {
      $self->$header_method( $header, "#ts", "device" );
   }

   # Print all of the rows
   foreach my $stat ( @stats ) {
      $self->$rows_method( $format, $cols, $stat );
   }

   $Diskstats::printed_lines = $max_lines
      if $Diskstats::printed_lines <= 0;
}

sub compute_line_ts {
   my ( $self, %args ) = @_;
   my $line_ts;
   if ( $self->show_timestamps() ) {
      $line_ts = $self->ts_line_for_timestamp();
      if ( $line_ts && $line_ts =~ /([0-9]{2}:[0-9]{2}:[0-9]{2})/ ) {
         $line_ts = $1;
      }
      else {
         $line_ts = scalar localtime($args{curr_ts});
         $line_ts =~ s/.*(\d\d:\d\d:\d\d).*/$1/;
      }
   }
   else {
      $line_ts = sprintf( "%5.1f", $args{first_ts} > 0
                              ? $args{curr_ts} - $args{first_ts}
                              : 0 );
   }
   return $line_ts;
}

sub compute_in_progress {
   my ( $self, $in_progress, $tot_in_progress ) = @_;
   return $in_progress;
}

sub compute_devs_in_group {
   return 1;
}

sub ts_line_for_timestamp {
   die 'You must override ts_line_for_timestamp() in a subclass';
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
# End Diskstats package
# ###########################################################################
