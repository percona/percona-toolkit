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
# DiskstatsMenu package
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
   'A'  => \&group_by,
   'D'  => \&group_by,
   'S'  => \&group_by,
   'i'  => \&hide_inactive_disks,
   'd'  => get_new_value_for( "redisplay_interval",
                       "Enter a new redisplay interval in seconds: " ),
   'z'  => get_new_value_for( "sample_time",
                       "Enter a new interval between samples in seconds: " ),
   'c'  => get_new_regex_for( "columns_regex",
                       "Enter a column pattern: " ),
   '/'  => get_new_regex_for( "devices_regex",
                       "Enter a disk/device pattern: " ),
         # Magical return value.
   'q'  => sub { return 'last' },
   'p'  => sub {
            print "Paused - press any key to continue\n";
            pause(@_);
            return;
         },
   ' '  => \&print_header,
   "\n" => \&print_header,
   '?'  => \&help,
);

my %input_to_object = (
      D  => "DiskstatsGroupByDisk",
      A  => "DiskstatsGroupByAll",
      S  => "DiskstatsGroupBySample",
   );

sub new {
   return bless {}, shift;
}

sub run_interactive {
   my ($self, %args) = @_;
   my @required_args = qw(OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($o) = @args{@required_args};

   # TODO Find out if there's a better way to do this.
   $o->{opts}->{current_group_by_obj}->{value} = undef;

   my ($tmp_fh, $filename, $child_pid, $child_fh);

   # Here's a big crux of the program. If we have a filename, we don't
   # need to fork and create a child, just read from it.
   if ( $filename = $args{filename} ) {
      open $tmp_fh, "<", $filename
         or die "Cannot open $filename: $OS_ERROR";
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
   $o->set("current_group_by_obj",
            $class->new( OptionParser => $o, interactive => 1 )
          );

   my $header_callback = $o->get("current_group_by_obj")
                           ->can("print_header");

   if ( $args{filename} ) {
      group_by(
         header_callback => $header_callback,
         select_obj      => $sel,
         OptionParser    => $o,
         filehandle      => $tmp_fh,
         input           => substr(ucfirst($group_by), 0, 1),
      );
      if ( !-t STDOUT && !tied *STDIN ) {
          # If we were passed down a file but aren't tied to a tty,
          # -and- STDIN isn't tied (so we aren't in testing mode),
          # then this is the end of the program.
          return 0
      }
   }

   ReadKeyMini::cbreak();
   my $run = 1;
   MAIN_LOOP:
   while ($run) {
      my $redisplay_interval = $o->get('redisplay-interval');
      if ( my $input = read_command_timeout($sel, $redisplay_interval ) ) {
         if ($actions{$input}) {
            my $ret = $actions{$input}->(
                              select_obj   => $sel,
                              OptionParser => $o,
                              input        => $input,
                              filehandle   => $tmp_fh,
                           ) || '';
            last MAIN_LOOP if $ret eq 'last';
         }
      }
      # As a possible source of confusion, note that this calls the group_by
      # _method_ in DiskstatsGroupBySomething, not the group_by _function_
      # defined below.
      $o->get("current_group_by_obj")
        ->group_by( filehandle => $tmp_fh );

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
   if ( !$args{filename} && !defined $o->get('iterations')
            && kill 0, $child_pid ) {
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
   my (%args)  = @_;
   my $samples = 0;

   STDIN->blocking(0);
   my $sel      = IO::Select->new(\*STDIN);
   my $filename = $args{filename};

   open my $fh, ">>", $filename
      or die "Cannot open $filename for appending: $OS_ERROR";

   GATHER_DATA:
   while ( $args{gather_while}->() ) {
      if ( read_command_timeout( $sel, $args{sampling_interval} ) ) {
         last GATHER_DATA;
      }
      open my $diskstats_fh, "<", "/proc/diskstats"
         or die "Cannot open /proc/diskstats: $OS_ERROR";

      my @to_print = timestamp();
      push @to_print, <$diskstats_fh>;

      # Lovely little method from IO::Handle: turns on autoflush,
      # prints, and then restores the original autoflush state.
      $fh->printflush(@to_print);
      close $diskstats_fh or die $OS_ERROR;

      $samples++;
      if ( defined($args{samples_to_gather})
            && $samples >= $args{samples_to_gather} ) {
         last GATHER_DATA;
      }
   }
   close $fh or die $OS_ERROR;
   return;
}

sub print_header {
   my (%args) = @_;
   my @required_args = qw( OptionParser );
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($o) = @args{@required_args};

   my $obj = $o->get("current_group_by_obj");
   my ($header) = $obj->design_print_formats();
   local $obj->{_print_header} = 1;
   return $obj->print_header($header, "#ts", "device");
}

sub group_by {
   my (%args)  = @_;

   my @required_args = qw( OptionParser input );
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($o, $input) = @args{@required_args};

   if ( ref( $o->get("current_group_by_obj") ) ne $input_to_object{$input} ) {
      # Particularly important! Otherwise we would depend on the
      # object's ->new being smart about discarding unrecognized
      # values.
      $o->set("current_group_by_obj", undef);
      # This would fail on a stricter constructor, so it probably
      # needs fixing.
      $o->set("current_group_by_obj",
               $input_to_object{$input}->new(
                                 OptionParser => $o,
                                 interactive  => 1,
                              )
             );
   }
   seek $args{filehandle}, 0, 0;

   # Just aliasing this for a bit.
   for my $obj ( $o->get("current_group_by_obj") ) {
      if ( $obj->isa("DiskstatsGroupBySample") ) {
         $obj->set_interactive(1);
      }
      else {
         $obj->set_interactive(0);
      }

      my $print_header;
      my $header_callback = $args{header_callback} || sub {
                              my ($self, @args) = @_;
                              $self->print_header(@args) unless $print_header++
                           };

      $obj->group_by(
               filehandle      => $args{filehandle},
               # Only print the header once, as if in interactive.
               header_callback => $header_callback,
            );
      $obj->set_interactive(1);
      $obj->{_print_header} = 0;
   }
}

sub help {
   my (%args)      = @_;
   my $obj         = $args{OptionParser}->get("current_group_by_obj");
   my $mode        = substr ref($obj), 16, 1;
   my $column_re   = $args{OptionParser}->get('columns-regex');
   my $device_re   = $args{OptionParser}->get('devices-regex');
   my $interval    = $obj->sample_time() || '(none)';
   my $disp_int    = $args{OptionParser}->get('redisplay-interval');
   my $inact_disk  = $obj->show_inactive() ? 'no' : 'yes';

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
      PTDEBUG && _d('No explicit filename passed in,',
                    'trying to get one from mktemp');
      chomp($filename = `mktemp -t pt-diskstats.$PID.XXXXXXXX`);
   }

   if ( $filename ) {
      open my $fh, "+>", $filename
         or die "Cannot open $filename: $OS_ERROR";
      return $fh, $filename;
   }
   else {
      PTDEBUG && _d("mktemp didn't return a filename,",
                    "trying to use File::Temp");
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
   my $obj     = $args{OptionParser}->get("current_group_by_obj");
   my $new_val = !$obj->show_inactive();

   $args{OptionParser}->set('show-inactive', !$new_val);
   $obj->set_show_inactive(!$new_val);

   return;
}

sub get_new_value_for {
   my ($looking_for, $message) = @_;
   (my $looking_for_o = $looking_for) =~ tr/_/-/;
   return sub {
      my (%args)       = @_;
      my $o            = $args{OptionParser};
      my $new_interval = get_blocking_input($message) || 0;
   
      die "Invalid timeout: $new_interval"
         unless looks_like_number($new_interval);

      my $obj = $o->get("current_group_by_obj");
      if ( my $setter = $obj->can("set_$looking_for") ) {
         $obj->$setter($new_interval);
      }
      $o->set($looking_for_o, $new_interval);
      return $new_interval;
   };
}

sub get_new_regex_for {
   my ($looking_for, $message) = @_;
   (my $looking_for_o = $looking_for) =~ tr/_/-/;
   $looking_for = "set_$looking_for";
   return sub {
      my (%args)    = @_;
      my $o         = $args{OptionParser};
      my $new_regex = get_blocking_input($message);
   
      local $EVAL_ERROR;
      if ( $new_regex && (my $re = eval { qr/$new_regex/i }) ) {
         $o->get("current_group_by_obj")
           ->$looking_for( $re );

         $o->set($looking_for_o, $new_regex);
      }
      elsif ( !$EVAL_ERROR && !$new_regex ) {
         my $re;
         if ( $looking_for =~ /device/ ) {
            # Special case code for device regexen. If they left the field
            # blank, we return to the original, magical behavior:
            $re = undef;
         }
         else {
            # This might seem weird, but an empty pattern is
            # somewhat magical, and basically just asking for trouble.
            # Instead we give them what awk would, a pattern that always
            # matches.
            $re = qr/.+/;
         }
         $o->get("current_group_by_obj")
           ->$looking_for( $re );
         $o->set($looking_for_o, '');
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
PTDEBUG && _d('Timestamp', $got_highres
                           ? "Using the pure Perl version"
                           : "Using the system's date command" );

sub timestamp {
   if ( $got_highres ) {
      # Can do everything in Perl
      # TS timestamp.nanoseconds ISO8601-timestamp
      my ( $seconds, $microseconds ) = Time::HiRes::gettimeofday();
      return sprintf( "TS %d.%d %s\n", $seconds,
                       $microseconds*1000, Transformers::ts($seconds) );
   }
   else {
      return `date +'TS %s.%N %F %T'`;
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
