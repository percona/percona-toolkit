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

use IO::Handle;
use IO::Select;
use Scalar::Util qw( looks_like_number );

use ReadKeyMini qw( ReadMode );

our $VERSION = '0.01';

my %actions = (
   'A' => \&group_by,
   'D' => \&group_by,
   'S' => \&group_by,
   's' => \&get_new_interval,
   'c' => get_new_x_regex("column_re", "Enter a column pattern: "),
   'd' => get_new_x_regex("disk_re", "Enter a disk/device pattern: "),
   'q' => sub { return 'last' },
   'p' => sub { print "Paused\n"; $_[0]->can_read() },
   '?' => \&help,
);

sub run {
   STDOUT->autoflush;
   STDIN->blocking(0);
   
   my $sel  = IO::Select->new(\*STDIN);
   my %opts = (
      interval => 1.5,
   );

   ReadMode("cbreak");
   MAIN_LOOP:
   while (1) {
      if ( $sel->can_read( $opts{interval} ) ) {
         while (my $got = <STDIN>) { # Should probably be sysread
            if ($actions{$got}) {
               last MAIN_LOOP unless $actions{$got}->($sel, \%opts) eq 'last';
            }
         }
      }
   }
   ReadMode("normal");

}

sub get_input {
   my ($message) = @_;

   STDIN->blocking(1);
   ReadMode("normal");

   print $message;
   chomp(my $new_opt = <STDIN>);

   ReadMode("cbreak");
   STDIN->blocking(0);
   return $new_opt;
}

sub get_new_interval {
   my ($args)      = @_;
   my $new_interval = get_input("Enter a redisplay interval: ");

   if ( looks_like_number($new_interval) ) {
      $args->{interval} = $new_interval;
   }
   else {
      die("invalid timeout specification");
   }
}

sub get_new_x_regex {
   my ($looking_for, $message) = @_;
   return sub {
      my ($args)   = @_;
      my $new_regex = get_input($message);
   
      if ( $new_regex && (my $re = eval { qr/$new_regex/ }) ) {
         $args->{$looking_for} = $re;
      }
      elsif (!$EVAL_ERROR && !$new_regex) {
         # This might seem weird, but an empty pattern is
         # somewhat magical, and basically just asking for trouble.
         # Instead we give them what awk would, a pattern that always
         # matches.
         $args->{$looking_for} = qr/(?=)/;
      }
      else {
         die("invalid regex specification: $EVAL_ERROR");
      }
   };
}

sub help {
   # XXX: TODO
   print <<'HELP'
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
}
1;
}
# ###########################################################################
# End DiskstatsMenu package
# ###########################################################################
