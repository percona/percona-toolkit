# This program is copyright 2012-2013 Percona Inc.
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
# Percona::WebAPI::Util package
# ###########################################################################
{
package Percona::WebAPI::Util;

use Digest::MD5 qw(md5_hex);

use Percona::WebAPI::Representation; 

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = (qw(resource_diff));

sub resource_diff {
   my ($x, $y) = @_;
   return 0 if !$x && !$y;
   return 1 if ($x && !$y) || (!$x && $y);
   return md5_hex(Percona::WebAPI::Representation::as_json($x))
       ne md5_hex(Percona::WebAPI::Representation::as_json($y));
}

1;
}
# ###########################################################################
# End Percona::WebAPI::Util package
# ###########################################################################
