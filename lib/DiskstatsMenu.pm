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
# DiskstatsMenu
# ###########################################################################
{
package DiskstatsMenu;

# DiskstatsMenu

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use IO::Handle;
use IO::Select;
use Scalar::Util qw( looks_like_number blessed );

use ReadKeyMini  qw( ReadMode );

require DiskstatsGroupByAll;
require DiskstatsGroupByDisk;
require DiskstatsGroupBySample;

our $VERSION = '0.01';

my %actions = (
   'A' => \&group_by,
   'D' => \&group_by,
   'S' => \&group_by,
   'i' => \&hide_inactive_disks,
   'd' => get_new_value_for( "redisplay_interval", "Enter a new redisplay interval in seconds: " ),
   'z' => get_new_value_for( "sample_time", "Enter a new interval between samples in seconds: " ),
   'c' => get_new_regex_for( "column_regex", "Enter a column pattern: " ),
   '/' => get_new_regex_for( "device_regex", "Enter a disk/device pattern: " ),
   'q' => sub { return 'last' },
   'p' => \&pause,
   '?' => \&help,
);

my %option_to_object = (
      D  => "DiskstatsGroupByDisk",
      A  => "DiskstatsGroupByAll",
      S  => "DiskstatsGroupBySample",
   );

my %object_to_option = reverse %option_to_object;

sub run_interactive {
   my ($self, %args) = @_;

   die "I need an [o] argument" unless $args{o} && blessed($args{o})
                                       && (
                                               $args{o}->isa("OptionParser")
                                            || $args{o}->can("get")
                                          );
   my $o = $args{o};

   my %opts = (
      save_samples       => $o->get('save-samples') || undef,
      samples_to_gather  => $o->get('iterations')   || undef,
      sampling_interval  => $o->get('interval')     || 1,
      redisplay_interval   => 1,
      sample_time        => $o->get('sample-time')  || 1,
      column_regex       => $o->get('columns')      || undef,
      device_regex       => $o->get('devices')      || undef,
      interactive        => 1,
      filter_zeroed_rows => !$o->get('zero-rows'),
   );

   for my $re_key ( grep { $opts{$_} } qw( column_regex device_regex ) ) {
      $opts{$re_key} = qr/$opts{$re_key}/i;
   }

   my ($tmp_fh, $filename, $child_pid, $child_fh);

   # Here's a big crux of the program. If we have a filename, we don't
   # need to fork and create a child, just read from it.
   if ( $args{filename} ) {
      $filename = $args{filename};
      open $tmp_fh, "<", $filename or die "Couldn't open [$filename]: $OS_ERROR";
   }
   else {
      ($tmp_fh, $filename) = file_to_use( $opts{save_samples} );

      # fork(), but future-proofing it in case we ever need to speak to
      # the child
      $child_pid = open $child_fh, "|-";
   
      if (not defined $child_pid) {
         die "Couldn't fork: $OS_ERROR";
      }
      
      if ( !$child_pid ) {
         # Child
   
         # Bit of helpful magic: Changes how the program's name is displayed,
         # so it's easier to track in things like ps.
         local $PROGRAM_NAME = "$PROGRAM_NAME (data-gathering daemon)";
   
         close($tmp_fh);
   
         open my $fh, ">>", $filename or die $!;
   
         gather_samples(
               gather_while      => sub { getppid() },
               samples_to_gather => $opts{samples_to_gather},
               sampling_interval => $opts{sampling_interval},
               filehandle        => $fh,
         );
   
         close $fh or die $!;
         unlink $filename unless $opts{save_samples};
         exit(0);
      }
   }

   local $SIG{CHLD} = 'IGNORE';
   local $SIG{PIPE} = 'IGNORE';

   STDOUT->autoflush;
   STDIN->blocking(0);

   my $sel    = IO::Select->new(\*STDIN);
   my $class  = $option_to_object{ substr ucfirst($o->get('group-by') || 'Disk'), 0, 1 };
   $opts{obj} = $class->new( %opts );

   if ( $args{filename} ) {
      group_by(
         header_cb  => sub { shift->print_header(@_) },
         select_obj => $sel,
         options    => \%opts,
         filehandle => $tmp_fh,
         got        => substr(ucfirst($o->get('group-by') || 'Disk'), 0, 1),
      );
   }

   ReadKeyMini::cbreak();
   MAIN_LOOP:
   while (1) {
      if ( my $got = read_command_timeout($sel, $opts{redisplay_interval} ) ) {
         if ($actions{$got}) {
            my $ret = $actions{$got}->(
                              select_obj => $sel,
                              options    => \%opts,
                              got        => $got,
                              filehandle => $tmp_fh,
                           ) || '';
            last MAIN_LOOP if $ret eq 'last';
         }
      }
      # As a possible source of confusion, note that this calls the group_by
      # _method_ in DiskstatsGroupBySomething, not the group_by _function_
      # defined below.
      $opts{obj}->group_by( filehandle => $tmp_fh, clear_state => 0 ) || 0;

      if ( eof $tmp_fh ) {
         # If we are gathering samples (don't have a filename), and we have a sample
         # limit (set by --iterations), the child process just calls it quits once
         # it gathers enough samples. When that happens, we are also done.
         if ( !$args{filename} && $opts{samples_to_gather} && kill 0, $child_pid ) {
            last MAIN_LOOP;
         }

         # This one comes from IO::Handle. I clears the eof flag
         # from a filehandle, so we can try reading from it again.
         $tmp_fh->clearerr;
      }
   }
   ReadKeyMini::cooked();

   if ( !$args{filename} ) {
      $child_fh->printflush("End\n");
      waitpid $child_pid, 0;
   }

   close($tmp_fh) or die "Couldn't close: $OS_ERROR";
   return;
}

sub read_command_timeout {
   my ($sel, $timeout) = @_;
   if ( $sel->can_read( $timeout ) ) {
      return scalar <STDIN>;
   }
   return;
}

sub gather_samples {
   my (%opts)  = @_;
   my $samples = 0;

   STDIN->blocking(0);
   my $sel     = IO::Select->new(\*STDIN);

   GATHER_DATA:
   while ( $opts{gather_while}->() ) {
      if ( read_command_timeout( $sel, $opts{sampling_interval} ) ) {
         last GATHER_DATA;
      }
      open my $diskstats_fh, "<", "/proc/diskstats"
            or die $!;

      my @to_print = `date +'TS %s.%N %F %T'`;
      push @to_print, <$diskstats_fh>;

      # Lovely little method from IO::Handle: turns on autoflush,
      # prints, and then restores the original autoflush state.
      $opts{filehandle}->printflush(@to_print);
      close $diskstats_fh or die $!;

      $samples++;
      if ( defined($opts{samples_to_gather}) && $samples >= $opts{samples_to_gather} ) {
         last GATHER_DATA;
      }
   }
   return;
}

sub group_by {
   my (%args) = @_;

   my $got = $args{got};

   if ( ref( $args{options}->{obj} ) ne $option_to_object{$got} ) {
      # Particularly important! Otherwise we would depend on the
      # object's ->new being smart about discarding unrecognized
      # values.
      delete $args{options}->{obj};
      # This would fail on a stricter constructor, so it probably
      # needs fixing.
      $args{options}->{obj} = $option_to_object{$got}->new( %{$args{options}});
   }
   seek $args{filehandle}, 0, 0;

   # Just aliasing this for a bit.
   for my $obj ( $args{options}->{obj} ) {
      if ( $obj->isa("DiskstatsGroupBySample") ) {
         $obj->interactive(1);
      }
      else {
         $obj->interactive(0);
      }
      $obj->group_by(
               filehandle => $args{filehandle},
               # Only print the header once, as if in interactive.
               header_cb => $args{header_cb} || sub {
                     my $print_header;
                     return sub {
                        unless ($print_header++) {
                           shift->print_header(@_)
                        }
                     };
                  }->(),
               );
      $obj->interactive(1);
      $obj->{_print_header} = 0;
   }
}

# regexp_pattern is used for pretty-printing regexen, since they can stringify to
# different things depending on the version of Perl. Unfortunately, 5.8
# lacks this, so in that version, we put in a facsimile.
BEGIN {
   local $EVAL_ERROR;

   eval { require re; re::regexp_pattern(qr//) };
   if ( $EVAL_ERROR ) {
      *regexp_pattern = sub {
            my ($re) = @_;
            (my $string_re = $re) =~ s/\A\(\?[^:]*?:(.*)\)\z/$1/sm;
            return $string_re;
         };
   }
   else {
      re->import("regexp_pattern");
   }
}

sub help {
   my (%args)      = @_;
   my $obj         = $args{options}->{obj};
   my $mode        = $object_to_option{ref($obj)};
   my ($column_re) = regexp_pattern( $obj->column_regex() );
   my ($device_re) = regexp_pattern( $obj->device_regex() );
   my $interval    = $obj->sample_time() || '(none)';
   my $disp_int    = $args{options}->{redisplay_interval} || '(none)';
   my $inact_disk  = $obj->filter_zeroed_rows() ? 'yes' : 'no';

   for my $re ( $column_re, $device_re ) {
      $re ||= '(none)';
      $re =~ s/^\Q(?=)\E$/(none)/;
   }

   print <<"HELP";
   You can control this program by key presses:
   ------------------- Key ------------------- ---- Current Setting ----
   A, D, S) Set the group-by mode              $mode
   c) Enter a Perl regex to match column names $column_re
   /) Enter a Perl regex to match disk names   $device_re
   z) Set the sample size in seconds           $interval
   i) Hide inactive disks                      $inact_disk
   d) Set the redisplay interval in seconds    $disp_int
   p) Pause the program
   q) Quit the program
   ------------------- Press any key to continue -----------------------
HELP
   pause(@_);
}

sub file_to_use {
   my ( $filename ) = @_;

   if ( !$filename ) {
      chomp($filename = `mktemp -t pt-diskstats.$PID.XXXXXXXX`);
   }

   if ( $filename ) {
      open my $fh, "<", $filename
         or die "Couldn't open $filename: $OS_ERROR";
      return $fh, $filename;
   }
   else {
      local $EVAL_ERROR;
      if ( !eval { require File::Temp } ) {
         die "Can't call mktemp nor load File::Temp. Install either of those, or pass in an explicit filename through --save-samples.";
      }
      my $dir = File::Temp::tempdir( CLEANUP => 1 );
      return File::Temp::tempfile(
                     "pt-diskstats.$PID.XXXXXXXX",
                     DIR      => $dir,
                     UNLINK   => 1,
                     OPEN     => 1,
                  );
   }
}

sub get_input {
   my ($message) = @_;

   STDIN->blocking(1);
   ReadKeyMini::cooked();

   print $message;
   chomp(my $new_opt = <STDIN>);

   ReadKeyMini::cbreak();
   STDIN->blocking(0);
   return $new_opt;
}

sub hide_inactive_disks {
   my (%args)       = @_;
   my $new_val      = !!get_input("Filter inactive rows? (Leave blank for 'No') ");

   $args{options}->{filter_zeroed_rows} = $new_val;
   $args{options}->{obj}->filter_zeroed_rows($new_val);
   return;
}

sub get_new_value_for {
   my ($looking_for, $message) = @_;
   return sub {
      my (%args)       = @_;
      my $new_interval = get_input($message);
   
      $new_interval ||= 0;
   
      if ( looks_like_number($new_interval) ) {
         if ( $args{options}->{obj}->can($looking_for) ) {
            $args{options}->{obj}->$looking_for($new_interval);
         }
         return $args{options}->{$looking_for} = $new_interval;
      }
      else {
         die("invalid timeout specification");
      }
   };
}

sub get_new_regex_for {
   my ($looking_for, $message) = @_;
   return sub {
      my (%args)   = @_;
      my $new_regex = get_input($message);
   
      local $EVAL_ERROR;
      if ( $new_regex && (my $re = eval { qr/$new_regex/i }) ) {
         $args{options}->{$looking_for} = $re;
      }
      elsif ( !$EVAL_ERROR && !$new_regex ) {
         # This might seem weird, but an empty pattern is
         # somewhat magical, and basically just asking for trouble.
         # Instead we give them what awk would, a pattern that always
         # matches.
         $args{options}->{$looking_for} = qr/(?=)/;
      }
      else {
         die("invalid regex specification: $EVAL_ERROR");
      }
      $args{options}->{obj}->$looking_for( $args{options}->{$looking_for} );
   };
}

sub pause {
   my (%args) = @_;
   STDIN->blocking(1);
   $args{select_obj}->can_read();
   STDIN->blocking(0);
   scalar <STDIN>;
   return;
}

1;
}
# ###########################################################################
# End DiskstatsMenu package
# ###########################################################################