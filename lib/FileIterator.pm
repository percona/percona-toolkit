# This program is copyright 2010-2011 Percona Ireland Ltd.
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
# FileIterator package
# ###########################################################################
{
# Package: FileIterator
# FileIterator make iterators that return filenames.
package FileIterator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      %args,
   };
   return bless $self, $class;
}

# get_file_itr() returns an iterator over the filenames passed in, which are
# typically from @ARGV on the command-line.  The special filename '-' is a
# synonym for STDIN, and an empty array is equivalent to reading only from
# STDIN.  Any non-readable files are warned about and skipped.  The iterator
# actually returns a tuple:
#   * A filehandle on the file, opened for reading.
#   * The file name, or undef for STDIN.
#   * The file size, or undef for STDIN.
# You should use it like this:
#  ( $fh, $name, $size ) = $next_fh->();
# At the time of requesting the next file from the iterator, the code will skip
# files that can't be opened, and just return the next one that can be.  This
# way the calling code doesn't have to do any error handling: it either gets a
# valid filehandle to work on next, or it's done.
sub get_file_itr {
   my ( $self, @filenames ) = @_;

   my @final_filenames;
   FILENAME:
   foreach my $fn ( @filenames ) {
      if ( !defined $fn ) {
         warn "Skipping undefined filename";
         next FILENAME;
      }
      if ( $fn ne '-' ) {
         if ( !-e $fn || !-r $fn ) {
            warn "$fn does not exist or is not readable";
            next FILENAME;
         }
      }
      push @final_filenames, $fn;
   }

   # If the list of files is empty, read from STDIN.
   if ( !@filenames ) {
      push @final_filenames, '-';
      PTDEBUG && _d('Auto-adding "-" to the list of filenames');
   }

   PTDEBUG && _d('Final filenames:', @final_filenames);
   return sub {
      while ( @final_filenames ) {
         my $fn = shift @final_filenames;
         PTDEBUG && _d('Filename:', $fn);
         if ( $fn eq '-' ) { # Magical STDIN filename.
            return (*STDIN, undef, undef);
         }
         open my $fh, '<', $fn or warn "Cannot open $fn: $OS_ERROR";
         if ( $fh ) {
            return ( $fh, $fn, -s $fn );
         }
      }
      return (); # Avoids $f being set to 0 in list context.
   };
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
# End FileIterator package
# ###########################################################################
