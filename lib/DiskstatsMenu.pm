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
# DiskstatsMenu package
# ###########################################################################
{
package DiskstatsMenu;

# DiskstatsMenu

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use POSIX qw( fmod :sys_wait_h );

use IO::Handle;
use IO::Select;
use Time::HiRes  qw( gettimeofday );
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
      # INTERNAL: For testing.
      if ( ref $filename ) {
         $tmp_fh = $filename;
         undef $args{filename};
      }
      else {
         open $tmp_fh, "<", $filename
            or die "Cannot open $filename: $OS_ERROR";
      }
   }
   else {
      $filename = $o->get('save-samples');

      if ( $filename ) {
         unlink $filename;
         open my $tmp_fh, "+>", $filename
            or die "Cannot open $filename: $OS_ERROR";
      }

      # fork(), but future-proofing it in case we ever need to speak to
      # the child
      $child_pid = open $child_fh, "-|";
   
      die "Cannot fork: $OS_ERROR" unless defined $child_pid;
      
      if ( !$child_pid ) {
         # Child
         STDOUT->autoflush(1);
         # Bit of helpful magic: Changes how the program's name is displayed,
         # so it's easier to track in things like ps.
         local $PROGRAM_NAME = "$PROGRAM_NAME (data-gathering daemon)";
   
         close $tmp_fh if $tmp_fh;
   
         PTDEBUG && _d("Child is [$PROGRAM_NAME] in ps aux and similar");

         gather_samples(
               gather_while      => sub { getppid() },
               samples_to_gather => $o->get('iterations'),
               filename          => $filename,
               sample_interval   => $o->get('interval'),
         );
         if ( $filename ) {
            unlink $filename unless $o->get('save-samples');
         }
         exit(0);
      }
      else {
         PTDEBUG && _d("Forked, child is", $child_pid);
         $tmp_fh = $child_fh;
         $tmp_fh->blocking(0);
         Time::HiRes::sleep(0.5);
      }
   }

   PTDEBUG && _d(
         $filename
         ? ("Using file", $filename)
         : "Not using a file to store samples");

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

   my $redraw = 0;

   if ( $args{filename} ) {
      PTDEBUG && _d("Passed a file from the command line,",
                    "rendering from scratch before looping");
      $redraw = 1;
      group_by(
         header_callback => $header_callback,
         select_obj      => $sel,
         OptionParser    => $o,
         filehandle      => $tmp_fh,
         input           => substr(ucfirst($group_by), 0, 1),
         redraw_all      => $redraw,
      );
      if ( !-t STDOUT && !tied *STDIN ) {
          # If we were passed down a file but aren't tied to a tty,
          # -and- STDIN isn't tied (so we aren't in testing mode),
          # then this is the end of the program.
          PTDEBUG && _d("Not connected to a tty and not in testing. Quitting");
          return 0
      }
   }

   ReadKeyMini::cbreak();
   my $run = 1;
   MAIN_LOOP:
   while ($run) {
      my $refresh_interval = $o->get('interval');
      my $time  = scalar Time::HiRes::gettimeofday();
      my $sleep = ($refresh_interval - fmod( $time, $refresh_interval ))+0.5;

      if ( my $input = read_command_timeout( $sel, $sleep ) ) {
         if ($actions{$input}) {
            PTDEBUG && _d("Got [$input] and have an action for it");
            my $ret = $actions{$input}->(
                              select_obj   => $sel,
                              OptionParser => $o,
                              input        => $input,
                              filehandle   => $tmp_fh,
                              redraw_all   => $redraw,
                           ) || '';
            last MAIN_LOOP if $ret eq 'last';

            # If we were passed a filename, render everything again after
            # a change of options, so long as those options aren't
            # A, S, D, <space>, or <enter>.
            if ( $args{filename}
                  && !grep { $input eq $_ } qw( A S D ), ' ', "\n" )
            {
               PTDEBUG && _d("Got a file from the command line, redrawing",
                             "from the beginning after getting an option");
               my $obj = $o->get("current_group_by_obj");
               # Force it to print the header
               $obj->clear_state( force => 1 );
               local $obj->{force_header} = 1;
               group_by(
                  redraw_all      => 1,
                  select_obj      => $sel,
                  OptionParser    => $o,
                  input           => substr(ref($obj), 16, 1),
                  filehandle      => $tmp_fh,
               );
            }
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
         PTDEBUG && _d("Child quit as expected after",
                       $o->get("iterations"),
                       "iterations. Quitting.");
         $run = 0;
      }
   }
   ReadKeyMini::cooked();

   # If we don't have a filename, the daemon might still be running.
   # If it is, ask it nicely to end, then wait.
   if ( $child_pid && !$args{filename} && !defined $o->get('iterations')
            && kill 0, $child_pid ) {
      # TODO
      kill 9, $child_pid;
      waitpid $child_pid, 0;
   }

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
   my $sample_interval = $args{sample_interval};
   my @fhs;

   if ( my $filename = $args{filename} ) {
      open my $fh, ">>", $filename
         or die "Cannot open $filename for appending: $OS_ERROR";
      push @fhs, $fh;
   }

   STDOUT->autoflush(1);
   push @fhs, \*STDOUT;

   for my $fh ( @fhs ) {
      $fh->autoflush(1);
   }

   {
      # If the next %10 is less than 20% of --interval, away,
      # wait till %10 then sample.
      # Otherwise, sample right away.
      my $time  = scalar(Time::HiRes::gettimeofday());
      my $sleep = $sample_interval - fmod( $time,
                              $sample_interval);
      PTDEBUG && _d("Child: Starting at [$time] "
                    . ($sleep < ($sample_interval * 0.2) ? '' : 'not ')
                    . "going to sleep");
      Time::HiRes::sleep($sleep) if $sleep < ($sample_interval * 0.2);

      open my $diskstats_fh, "<", "/proc/diskstats"
         or die "Cannot open /proc/diskstats: $OS_ERROR";

      my @to_print = timestamp();
      push @to_print, <$diskstats_fh>;
   
      for my $fh ( @fhs ) {
         print { $fh } @to_print;
      }
      close $diskstats_fh or die $OS_ERROR;
   }

   GATHER_DATA:
   while ( $args{gather_while}->() ) {
      my $time_of_day = scalar(Time::HiRes::gettimeofday());
      my $sleep = $sample_interval
             - fmod( $time_of_day, $sample_interval );
      Time::HiRes::sleep($sleep);

      open my $diskstats_fh, "<", "/proc/diskstats"
         or die "Cannot open /proc/diskstats: $OS_ERROR";

      my @to_print = timestamp();
      push @to_print, <$diskstats_fh>;

      for my $fh ( @fhs ) {
         # Lovely little method from IO::Handle: turns on autoflush,
         # prints, and then restores the original autoflush state.
         print { $fh } @to_print;
      }
      close $diskstats_fh or die $OS_ERROR;

      $samples++;
      if ( defined($args{samples_to_gather})
            && $samples >= $args{samples_to_gather} ) {
         last GATHER_DATA;
      }
   }
   pop @fhs; # STDOUT
   for my $fh ( @fhs ) {
      close $fh or die $OS_ERROR;
   }
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
   return $obj->force_print_header($header, "#ts", "device");
}

sub group_by {
   my (%args)  = @_;

   my @required_args = qw( OptionParser input );
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($o, $input) = @args{@required_args};

   my $old_obj = $o->get("current_group_by_obj");

   if ( ref( $o->get("current_group_by_obj") ) ne $input_to_object{$input} ) {
      # Particularly important! Otherwise we would depend on the
      # object's ->new being smart about discarding unrecognized
      # values.
      $o->set("current_group_by_obj", undef);
      my $new_obj = $input_to_object{$input}->new(OptionParser=>$o, interactive => 1);
      $o->set( "current_group_by_obj", $new_obj );

      # Data shared between all the objects.
      # Current
      $new_obj->{_stats_for}  = $old_obj->{_stats_for};
      $new_obj->set_curr_ts($old_obj->curr_ts());

      # Previous
      $new_obj->{_prev_stats_for}  = $old_obj->{_prev_stats_for};
      $new_obj->set_prev_ts($old_obj->prev_ts());

      # First
      $new_obj->{_first_stats_for} = $old_obj->{_first_stats_for};
      $new_obj->set_first_ts($old_obj->first_ts());

      # If we can't redraw the entire file, because there isn't a file,
      # just settle for reprinting the header.
      print_header(%args) unless $args{redraw_all};
   }

   # Just aliasing this for a bit.
   for my $obj ( $o->get("current_group_by_obj") ) {
      if ( $args{redraw_all} ) {
         seek $args{filehandle}, 0, 0;
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
      }
      $obj->set_interactive(1);
      $obj->set_force_header(0);
   }

}

sub help {
   my (%args)     = @_;
   my $obj        = $args{OptionParser}->get("current_group_by_obj");
   my $mode       = substr ref($obj), 16, 1;
   my $column_re  = $args{OptionParser}->get('columns-regex');
   my $device_re  = $args{OptionParser}->get('devices-regex');
   my $interval   = $obj->sample_time() || '(none)';
   my $disp_int   = $args{OptionParser}->get('interval');
   my $inact_disk = $obj->show_inactive() ? 'no' : 'yes';

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
   p) Pause the program
   q) Quit the program
   space) Print headers
   ------------------- Press any key to continue -----------------------
HELP

   pause(%args);
   return;
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

   $args{OptionParser}->set('show-inactive', $new_val);
   $obj->set_show_inactive($new_val);

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
         unless looks_like_number($new_interval)
                  && ($new_interval = int($new_interval));

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

sub timestamp {
   # TS timestamp.nanoseconds ISO8601-timestamp
   my ($s, $m) = Time::HiRes::gettimeofday();
   return sprintf( "TS %d.%09d %s\n", $s, $m*1000, Transformers::ts( $s ) );
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
