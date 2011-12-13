# This program is copyright 2010-2011 Percona Inc.
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
# ReadKeyMini
# ###########################################################################
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

# Package: ReadKeyMini
# ReadKeyMini is a wrapper around Term::ReadKey. If that's available,
# we use ReadMode and GetTerminalSize from there. Otherwise, we use homebrewn
# definitions.

use warnings;
use strict;
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Carp  qw( croak );
use POSIX qw( :termios_h );

use base  qw( Exporter );

BEGIN {
   our @EXPORT_OK = qw( ReadMode GetTerminalSize );
   my $have_readkey = eval { require Term::ReadKey };

   if ($have_readkey) {
      Term::ReadKey->import(@EXPORT_OK);
   }
   else {
      *ReadMode        = *Term::ReadKey::ReadMode        = \&_ReadMode;
      *GetTerminalSize = *Term::ReadKey::GetTerminalSize = \&_GetTerminalSize;
   }
}

our $VERSION = '0.01';

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
   my $term     = POSIX::Termios->new();
   $term->getattr($fd_stdin);
   my $oterm = $term->getlflag();

   my $echo   = ECHO | ECHOK | ICANON;
   my $noecho = $oterm & ~$echo;

   sub _ReadMode {
      my $mode = $modes{ $_[0] };
      if ( $mode == $modes{normal} ) {
            cooked();
      }
      elsif ( $mode == $modes{cbreak} || $mode == $modes{noecho} ) {
            cbreak( $mode == $modes{noecho} ? $noecho : $oterm );
      }
      else {
            croak("ReadMore('$_[0]') not supported");
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
   }

   END { cooked() }

}

sub readkey {
    my $key = '';
    cbreak();
    sysread(STDIN, $key, 1);
    my $timeout = 0.1;
    if ( $key eq "\033" ) { # Ugly and broken hack, but good enough for the two minutes it took to write.
        {
            my $x = '';
            STDIN->blocking(0);
            sysread(STDIN, $x, 2);
            STDIN->blocking(1);
            $key .= $x;
            redo if $key =~ /\[[0-2](?:[0-9];)?$/
        }
    }
    cooked();
    return $key;
}

# As per perlfaq8:

sub _GetTerminalSize {
   if ( @_ ) {
      croak "My::Term::ReadKey doesn't implement GetTerminalSize with arguments";
   }
   eval { require 'sys/ioctl.ph' };
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
   open( TTY, "+<", "/dev/tty" ) or croak "No tty: $OS_ERROR";
   my $winsize = '';
   unless ( ioctl( TTY, &TIOCGWINSZ, $winsize ) ) {
      croak sprintf "$0: ioctl TIOCGWINSZ (%08x: $OS_ERROR)\n", &TIOCGWINSZ;
   }
   my ( $row, $col, $xpixel, $ypixel ) = unpack( 'S4', $winsize );
   return ( $col, $row, $xpixel, $ypixel );
}

}

1;
# ###########################################################################
# End ReadKeyMini package
# ###########################################################################
