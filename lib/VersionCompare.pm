# This program is copyright 2016 Percona LLC.
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
# VersionCompare package
# ###########################################################################

# The purpose of this very simple module is to compare MySQL version strings
# There's VersionParser and the perl core "version" module, but I wanted
# something simpler and that could grow incrementally

{
package VersionCompare;

use strict;
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub cmp {
   my ($v1, $v2) = @_;

   # Remove all but numbers and dots. 
   # Assume simple 1.2.3 style
   $v1 =~ s/[^\d\.]//;
   $v2 =~ s/[^\d\.]//;

   my @a = ( $v1 =~ /(\d+)\.?/g ); 
   my @b = ( $v2 =~ /(\d+)\.?/g ); 
   foreach my $n1 (@a) {
      $n1 += 0; #convert to number
      if (!@b) {
         # b ran out of digits, a is larger
         return 1;
      }  
      my $n2 = shift @b;
      $n2 += 0; # convert to number
      if ($n1 == $n2) {
          # still tied?, fetch next 
          next;
      }
      else {
         # difference! return result
         return $n1 <=> $n2;
      }  
   }  
   # b still has digits? it's larger, else it's a tie
   return @b ? -1 : 0;
}


1;
}
# ###########################################################################
# End VersionCompare package
# ###########################################################################
