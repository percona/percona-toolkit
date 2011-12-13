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

use warnings;
use strict;
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use re qw( regexp_pattern );

use IO::Handle;
use IO::Select;
use Scalar::Util qw( looks_like_number );
use File::Temp   qw( tempfile tempdir  );

use ReadKeyMini qw( ReadMode );

use DiskstatsGroupByAll;
use DiskstatsGroupByDisk;
use DiskstatsGroupBySample;

our $VERSION = '0.01';

my %actions = (
   'A' => \&group_by,
   'D' => \&group_by,
   'S' => \&group_by,
   's' => \&get_new_interval,
   'c' => get_new_x_regex("column_re", "Enter a column pattern: "),
   'd' => get_new_x_regex("disk_re", "Enter a disk/device pattern: "),
   'q' => sub { return 'last' },
   'p' => \&pause,
   '?' => \&help,
);

sub run {
   my ($self, %args) = @_;

   my %opts = (
      keep_file         => undef,
      samples_to_gather => undef,
      sample_interval   => 3,
      interval          => 0.5,
      device_regex      => qr/sda/,
      interactive       => 1,
   );

   my $dir = tempdir( CLEANUP => 1 );
   my ($tmp_fh, $filename) = tempfile(
                           "diskstats-samples.XXXXXXXX",
                           DIR      => $dir,
                           UNLINK   => 1,
                           OPEN     => 1,
                        );
   my $pid = open my $child_fh, "|-";

   if (not defined $pid) {
      die "Couldn't fork: $OS_ERROR";
   }
   
   if ( !$pid ) {
      # Child

      # Bit of helpful magic: Changes how the program's name is displayed,
      # so it's easier to track in things like ps.
      local $PROGRAM_NAME = "$PROGRAM_NAME (data-gathering daemon)";

      close($tmp_fh);

      open my $fh, ">>", $filename or die $!;

      while ( getppid() ) {
         sleep($opts{sample_interval});
         open my $diskstats_fh, "<", "/proc/diskstats"
               or die $!;

         my @to_print = <$diskstats_fh>;
         push @to_print, `date +'TS %s.%N %F %T'`;

         # Lovely little method from IO::Handle: turns on autoflush,
         # prints, and then restores the original autoflush state.
         $fh->printflush(@to_print);

         close $diskstats_fh or die $!;
      }
      close $fh or die $!;
      unlink $filename unless $opts{keep_file};
      exit(0);
   }

   STDOUT->autoflush;
   STDIN->blocking(0);

   my $sel  = IO::Select->new(\*STDIN);

   my $lines_read = 0;

   $opts{obj} = DiskstatsGroupByDisk->new(%opts);

   ReadKeyMini::cbreak();
   warn $filename;
   MAIN_LOOP:
   while (1) {
      if ( $sel->can_read( $opts{interval} ) ) {
         while (my $got = <STDIN>) { # Should probably be sysread
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
      }
      $lines_read += $opts{obj}->group_by( filehandle => $tmp_fh ) || 0;
      $tmp_fh->clearerr if eof $tmp_fh;
   }
   ReadKeyMini::cooked();
   kill 9, $pid;
   close($tmp_fh);
   return;
}

{
   my %objects = (
         D  => "DiskstatsGroupByDisk",
         A  => "DiskstatsGroupByAll",
         S  => "DiskstatsGroupBySample",
      );

   sub group_by {
      my (%args) = @_;

      my $got = $args{got};

      if ( ref( $args{options}->{obj} ) ne $objects{$got} ) {
         delete $args{options}->{obj};
         # This would fail on a stricter constructor, so it probably
         # needs fixing.
         $args{options}->{obj} = $objects{$got}->new( %{$args{options}} );
      }
      seek $args{filehandle}, 0, 0;
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

sub get_new_interval {
   my (%args)       = @_;
   my $new_interval = get_input("Enter a redisplay interval: ");

   $new_interval ||= 0;

   if ( looks_like_number($new_interval) ) {
      return $args{options}->{interval} = $new_interval;
   }
   else {
      die("invalid timeout specification");
   }
}

sub get_new_x_regex {
   my ($looking_for, $message) = @_;
   return sub {
      my (%args)   = @_;
      my $new_regex = get_input($message);
   
      if ( $new_regex && (my $re = eval { qr/$new_regex/i }) ) {
         $args{options}->{$looking_for} = $re;
      }
      elsif (!$EVAL_ERROR && !$new_regex) {
         # This might seem weird, but an empty pattern is
         # somewhat magical, and basically just asking for trouble.
         # Instead we give them what awk would, a pattern that always
         # matches.
         $args{options}->{$looking_for} = qr/(?=)/;
      }
      else {
         die("invalid regex specification: $EVAL_ERROR");
      }
   };
}

sub help {
   # XXX: TODO
   print <<'HELP';
   You can control this program by key presses:
   ------------------- Key ------------------- ---- Current Setting ----
   A, D, S) Set the group-by mode              \$opt{OPT_g}
   c) Enter an awk regex to match column names \$opt{OPT_c}
   d) Enter an awk regex to match disk names   \$opt{OPT_d}
   i) Set the sample size in seconds           \$opt{OPT_i}
   s) Set the redisplay interval in seconds    \$opt{OPT_s}
   p) Pause the program
   q) Quit the program
   ------------------- Press any key to continue -----------------------
HELP
   pause(@_);
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

__PACKAGE__->run(@ARGV) unless caller;

}
# ###########################################################################
# End DiskstatsMenu package
# ###########################################################################