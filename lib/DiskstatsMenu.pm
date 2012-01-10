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
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use POSIX qw( :sys_wait_h );

use IO::Handle;
use IO::Select;
use Scalar::Util qw( looks_like_number blessed );

use ReadKeyMini  qw( ReadMode );
use Transformers qw( ts       );

require DiskstatsGroupByAll;
require DiskstatsGroupByDisk;
require DiskstatsGroupBySample;

my %actions = (
   'A' => \&group_by,
   'D' => \&group_by,
   'S' => \&group_by,
   'i' => \&hide_inactive_disks,
   'd' => get_new_value_for( "redisplay_interval",
                       "Enter a new redisplay interval in seconds: " ),
   'z' => get_new_value_for( "sample_time",
                       "Enter a new interval between samples in seconds: " ),
   'c' => get_new_regex_for( "column_regex",
                       "Enter a column pattern: " ),
   '/' => get_new_regex_for( "device_regex",
                       "Enter a disk/device pattern: " ),
         # Magical return value.
   'q' => sub { return 'last' },
   'p' => sub {
         print "Paused - press any key to continue\n";
         pause(@_);
         return;
      },
   '?' => \&help,
);

my %input_to_object = (
      D  => "DiskstatsGroupByDisk",
      A  => "DiskstatsGroupByAll",
      S  => "DiskstatsGroupBySample",
   );

sub new {
   bless {}, shift;
}

sub run_interactive {
   my ($self, %args) = @_;
   my @required_args = qw(OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($o) = @args{@required_args};

   my %opts = (
      interactive        => 1,
      OptionParser       => $o,
   );

   my ($tmp_fh, $filename, $child_pid, $child_fh);

   # Here's a big crux of the program. If we have a filename, we don't
   # need to fork and create a child, just read from it.
   if ( $filename = $args{filename} ) {
      open $tmp_fh, "<", $filename or die "Cannot open $filename: $OS_ERROR";
   }
   else {
      ($tmp_fh, $filename) = file_to_use( $o->get('save-samples') );

      # fork(), but future-proofing it in case we ever need to speak to
      # the child
      $child_pid = open $child_fh, "|-";
   
      die "Cannot fork: $OS_ERROR" unless defined $child_pid;
      
      if ( !$child_pid ) {
         # Child
   
         # Bit of helpful magic: Changes how the program's name is displayed,
         # so it's easier to track in things like ps.
         local $PROGRAM_NAME = "$PROGRAM_NAME (data-gathering daemon)";
   
         close $tmp_fh;
   
         gather_samples(
               gather_while      => sub { getppid() },
               samples_to_gather => $o->get('iterations'),
               sampling_interval => $o->get('interval'),
               filename          => $filename,
         );
   
         unlink $filename unless $o->get('save-samples');
         exit(0);
      }
   }

   PTDEBUG && _d("Using filename", $filename);

   # I don't think either of these are needed actually, since piped opens
   # are supposed to deal with children on their own, but it doesn't hurt.
   local $SIG{CHLD} = 'IGNORE';
   local $SIG{PIPE} = 'IGNORE';

   STDOUT->autoflush;
   STDIN->blocking(0);

   my $sel      = IO::Select->new(\*STDIN);
   my $group_by = $o->get('group-by') || 'disk';
   my $class    =  $group_by =~ m/disk/i   ? 'DiskstatsGroupByDisk'
                 : $group_by =~ m/sample/i ? 'DiskstatsGroupBySample'
                 : $group_by =~ m/all/i    ? 'DiskstatsGroupByAll'
                 : die "Invalid --group-by: $group_by";
   $opts{current_group_by_obj}   = $class->new( %opts );

   if ( $args{filename} ) {
      group_by(
         header_callback  => sub { shift->print_header(@_) },
         select_obj => $sel,
         options    => \%opts,
         filehandle => $tmp_fh,
         input      => substr(ucfirst($group_by), 0, 1),
      );
   }

   ReadKeyMini::cbreak();
   my $run = 1;
   MAIN_LOOP:
   while ($run) {
      if ( my $input = read_command_timeout($sel, $o->get('redisplay-interval') ) ) {
         if ($actions{$input}) {
            my $ret = $actions{$input}->(
                              select_obj => $sel,
                              options    => \%opts,
                              input      => $input,
                              filehandle => $tmp_fh,
                           ) || '';
            last MAIN_LOOP if $ret eq 'last';
         }
      }
      # As a possible source of confusion, note that this calls the group_by
      # _method_ in DiskstatsGroupBySomething, not the group_by _function_
      # defined below.
      $opts{current_group_by_obj}->group_by( filehandle => $tmp_fh ) || 0;

      if ( eof $tmp_fh ) {
         # This one comes from IO::Handle. I clears the eof flag
         # from a filehandle, so we can try reading from it again.
         $tmp_fh->clearerr;
      }
      # If we are gathering samples (don't have a filename), and
      # we have a sample limit (set by --iterations), the child
      # process just calls it quits once it gathers enough samples.
      # When that happens, we are also done.
      if ( !$args{filename} && $o->get('iterations')
            && waitpid($child_pid, WNOHANG) != 0 ) {
         $run = 0;
      }
   }
   ReadKeyMini::cooked();

   # If we don't have a filename, the daemon might still be running.
   # If it is, ask it nicely to end, then wait.
   if ( !$args{filename} && !defined $o->get('iterations') && kill 0, $child_pid ) {
      $child_fh->printflush("End\n");
      waitpid $child_pid, 0;
   }

   close $tmp_fh or die "Cannot close: $OS_ERROR";
   return 0; # Exit status
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
   my $sel      = IO::Select->new(\*STDIN);
   my $filename = $opts{filename};

   GATHER_DATA:
   while ( $opts{gather_while}->() ) {
      if ( read_command_timeout( $sel, $opts{sampling_interval} ) ) {
         last GATHER_DATA;
      }
      open my $fh, ">>", $filename or die $OS_ERROR;
      open my $diskstats_fh, "<", "/proc/diskstats"
            or die $OS_ERROR;

      my @to_print = timestamp();
      push @to_print, <$diskstats_fh>;

      # Lovely little method from IO::Handle: turns on autoflush,
      # prints, and then restores the original autoflush state.
      $fh->printflush(@to_print);
      close $diskstats_fh or die $OS_ERROR;
      close $fh or die $OS_ERROR;

      $samples++;
      if ( defined($opts{samples_to_gather})
            && $samples >= $opts{samples_to_gather} ) {
         last GATHER_DATA;
      }
   }
   return;
}

sub group_by {
   my (%args)  = @_;

   my @required_args = qw( options input );
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($options, $input) = @args{@required_args};

   if ( ref( $args{options}->{current_group_by_obj} ) ne $input_to_object{$input} ) {
      # Particularly important! Otherwise we would depend on the
      # object's ->new being smart about discarding unrecognized
      # values.
      delete $args{options}->{current_group_by_obj};
      # This would fail on a stricter constructor, so it probably
      # needs fixing.
      $args{options}->{current_group_by_obj} = $input_to_object{$input}->new(
                                 %{$args{options}}
                              );
   }
   seek $args{filehandle}, 0, 0;

   # Just aliasing this for a bit.
   for my $obj ( $args{options}->{current_group_by_obj} ) {
      if ( $obj->isa("DiskstatsGroupBySample") ) {
         $obj->interactive(1);
      }
      else {
         $obj->interactive(0);
      }
      $obj->group_by(
               filehandle => $args{filehandle},
               # Only print the header once, as if in interactive.
               header_callback => $args{header_callback} || sub {
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

sub help {
   my (%args)      = @_;
   my $obj         = $args{options}->{current_group_by_obj};
   my $mode        = substr ref($obj), 16, 1;
   my $column_re   = $args{options}->{OptionParser}->get('columns');
   my $device_re   = $args{options}->{OptionParser}->get('devices');
   my $interval    = $obj->sample_time() || '(none)';
   my $disp_int    = $args{options}->{OptionParser}->get('redisplay-interval');
   my $inact_disk  = $obj->filter_zeroed_rows() ? 'yes' : 'no';

   for my $re ( $column_re, $device_re ) {
      $re ||= '(none)';
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
   return;
}

sub file_to_use {
   my ( $filename ) = @_;

   if ( !$filename ) {
      PTDEBUG && _d('No explicit filename passed in, trying to get one from mktemp');
      chomp($filename = `mktemp -t pt-diskstats.$PID.XXXXXXXX`);
   }

   if ( $filename ) {
      open my $fh, "+>", $filename
         or die "Cannot open $filename: $OS_ERROR";
      return $fh, $filename;
   }
   else {
      PTDEBUG && _d("mktemp didn't return a filename, trying to use File::Temp");
      local $EVAL_ERROR;
      if ( !eval { require File::Temp } ) {
         die "Can't call mktemp nor load File::Temp.",
             " Install either of those, or pass in an explicit",
             " filename through --save-samples.";
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

sub get_blocking_input {
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
   my (%args)  = @_;
   my $new_val = get_blocking_input("Filter inactive rows? (Leave blank for 'No') ");

   # Eeep. In OptionParser, "true" means show; in Diskstats, "true" means hide.
   # Thus !$new_val for OptionParser
   $args{options}->{OptionParser}->set('zero-rows', !$new_val);
   $args{options}->{current_group_by_obj}->set_filter_zeroed_rows($new_val);

   return;
}

sub get_new_value_for {
   my ($looking_for, $message) = @_;
   (my $looking_for_o = $looking_for) =~ tr/_/-/;
   return sub {
      my (%args)       = @_;
      my $new_interval = get_blocking_input($message) || 0;
   
      die "Invalid timeout: $new_interval"
         unless looks_like_number($new_interval);

      if ( my $setter = $args{options}->{current_group_by_obj}->can("set_$looking_for") )
      {
         $args{options}->{current_group_by_obj}->$setter($new_interval);
      }
      $args{options}->{OptionParser}->set($looking_for_o, $new_interval);
      return $new_interval;
   };
}

sub get_new_regex_for {
   my ($looking_for, $message) = @_;
   (my $looking_for_o = $looking_for) =~ s/_.*$/s/;
   return sub {
      my (%args)    = @_;
      my $new_regex = get_blocking_input($message);
   
      local $EVAL_ERROR;
      if ( $new_regex && (my $re = eval { qr/$new_regex/i }) ) {
         $args{options}->{current_group_by_obj}->$looking_for( $re );
         $args{options}->{OptionParser}->set($looking_for_o, $new_regex);
      }
      elsif ( !$EVAL_ERROR && !$new_regex ) {
         # This might seem weird, but an empty pattern is
         # somewhat magical, and basically just asking for trouble.
         # Instead we give them what awk would, a pattern that always
         # matches.
         $args{options}->{current_group_by_obj}->$looking_for( qr/(?=)/ );
         $args{options}->{OptionParser}->set($looking_for_o, '');
      }
      else {
         die "invalid regex specification: $EVAL_ERROR";
      }
      return;
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

my $got_highres = eval { require Time::HiRes };
sub timestamp {
   if ( $got_highres ) {
      # Can do everything in Perl
      # TS timestamp.nanoseconds ISO8601-timestamp
      PTDEBUG && _d('Timestamp', "Using the pure Perl version");
      my ( $seconds, $microseconds ) = Time::HiRes::gettimeofday();
      return sprintf( "TS %d.%d %s\n", $seconds,
                       $microseconds*1000, Transformers::ts($seconds) );
   }
   else {
      PTDEBUG && _d('Timestamp', "Using the system's date command");
      `date +'TS %s.%N %F %T'`;
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
# End DiskstatsMenu package
# ###########################################################################