# This program is copyright 2010-2012 Percona Ireland Ltd.
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
# ReadKeyMini package
# ###########################################################################

# Package: ReadKeyMini
# ReadKeyMini is a wrapper around Term::ReadKey. If that's available,
# we use ReadMode and GetTerminalSize from there. Otherwise, we use homebrewn
# definitions.

BEGIN {

package ReadKeyMini;
# Here be magic. We lie to %INC and say that someone already pulled us from
# the filesystem. Which might be true, if this is inside a .pm file, but
# might not be, if we are part of the big file. The spurious BEGINs are mostly
# unnecesary, but if we aren't inside a .pm and something uses us, import or
# EXPORT_OK might not yet be defined. Though that probably won't help.
# Costs us nothing though, so worth trying. Putting this on top of the file
# would solve the issue.
BEGIN { $INC{"ReadKeyMini.pm"} ||= 1 }

use warnings;
use strict;
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use POSIX qw( :termios_h );
use Fcntl qw( F_SETFL F_GETFL );

use base  qw( Exporter );

BEGIN {
   # Fake Term::ReadKey. We clobber our own glob,
   # ReadKeyMini::Function, and the Term::ReadKey glob, so callers can
   # both import it if requested, or even use the fully-qualified name
   # without issues.
   our @EXPORT_OK = qw( GetTerminalSize ReadMode );
   *ReadMode        = *Term::ReadKey::ReadMode        = \&_ReadMode;
   *GetTerminalSize = *Term::ReadKey::GetTerminalSize = \&_GetTerminalSize;
}

my %modes = (
   original    => 0,
   restore     => 0,
   normal      => 1,
   noecho      => 2,
   cbreak      => 3,
   raw         => 4,
   'ultra-raw' => 5,
);

# This primarily comes from the Perl Cookbook, recipe 15.8
{
   my $fd_stdin = fileno(STDIN);
   my $flags;
   unless ( $PerconaTest::DONT_RESTORE_STDIN ) {
      $flags = fcntl(STDIN, F_GETFL, 0)
         or warn "Error getting STDIN flags with fcntl: $OS_ERROR";
   }
   my $term     = POSIX::Termios->new();
   $term->getattr($fd_stdin);
   my $oterm    = $term->getlflag();
   my $echo     = ECHO | ECHOK | ICANON;
   my $noecho   = $oterm & ~$echo;

   sub _ReadMode {
      my $mode = $modes{ $_[0] };
      if ( $mode == $modes{normal} ) {
         cooked();
      }
      elsif ( $mode == $modes{cbreak} || $mode == $modes{noecho} ) {
         cbreak( $mode == $modes{noecho} ? $noecho : $oterm );
      }
      else {
         die("ReadMore('$_[0]') not supported");
      }
   }

   sub cbreak {
      my ($lflag) = $_[0] || $noecho; 
      $term->setlflag($lflag);
      $term->setcc( VTIME, 1 );
      $term->setattr( $fd_stdin, TCSANOW );
   }

   sub cooked {
      $term->setlflag($oterm);
      $term->setcc( VTIME, 0 );
      $term->setattr( $fd_stdin, TCSANOW );
      if ( !$PerconaTest::DONT_RESTORE_STDIN ) {
         fcntl(STDIN, F_SETFL, int($flags))
            or warn "Error restoring STDIN flags with fcntl: $OS_ERROR";
      }
   }

   END { cooked() }
}

sub readkey {
   my $key = '';
   cbreak();
   sysread(STDIN, $key, 1);
   my $timeout = 0.1;
   if ( $key eq "\033" ) {
      # Ugly and broken hack, but good enough for the two minutes it took
      # to write. Namely, Ctrl escapes, the F-NUM keys, and other stuff
      # you can send from the keyboard take more than one "character" to
      # represent, and would be wrong to break into pieces.
      my $x = '';
      STDIN->blocking(0);
      sysread(STDIN, $x, 2);
      STDIN->blocking(1);
      $key .= $x;
      redo if $key =~ /\[[0-2](?:[0-9];)?$/
   }
   cooked();
   return $key;
}

# As per perlfaq8:

BEGIN {
   eval { no warnings; local $^W; require 'sys/ioctl.ph' };
   if ( !defined &TIOCGWINSZ ) {
      *TIOCGWINSZ = sub () {
            # Very few systems actually have ioctl.ph, thus it comes to this.
            # These seem to be good enough, for now. See:
            # http://stackoverflow.com/a/4286840/536499
              $^O eq 'linux'   ? 0x005413
            : $^O eq 'solaris' ? 0x005468
            :                    0x40087468;
      };
   }
}

sub _GetTerminalSize {
   if ( @_ ) {
      die "My::Term::ReadKey doesn't implement GetTerminalSize with arguments";
   }

   my $cols = $ENV{COLUMNS} || 80;
   my $rows = $ENV{LINES}   || 24;

   if ( open( TTY, "+<", "/dev/tty" ) ) { # Got a tty
      my $winsize = '';
      if ( ioctl( TTY, &TIOCGWINSZ, $winsize ) ) {
         ( $rows, $cols, my ( $xpixel, $ypixel ) ) = unpack( 'S4', $winsize );
         return ( $cols, $rows, $xpixel, $ypixel );
      }
   }

   if ( $rows = `tput lines 2>/dev/null` ) {
      chomp($rows);
      chomp($cols = `tput cols`);
   }
   elsif ( my $stty = `stty -a 2>/dev/null` ) {
      ($rows, $cols) = $stty =~ /([0-9]+) rows; ([0-9]+) columns;/;
   }
   else {
      ($cols, $rows) = @ENV{qw( COLUMNS LINES )};
      $cols ||= 80;
      $rows ||= 24;
   }

   return ( $cols, $rows );
}

}

1;
# ###########################################################################
# End ReadKeyMini package
# ###########################################################################
