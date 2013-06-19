# This program is copyright 2013 Percona Ireland Ltd.
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
# Safeguards package
# ###########################################################################
package Safeguards;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ($class, %args) = @_;
   my $self = {
      disk_bytes_free => $args{disk_bytes_free} || 104857600,  # 100 MiB
      disk_pct_free   => $args{disk_pct_free}   || 5,
   };
   return bless $self, $class;
}

sub get_disk_space {
   my ($self, %args) = @_;
   my $filesystem = $args{filesystem} || $ENV{PWD};

   # Filesystem   1024-blocks     Used Available Capacity  Mounted on
   # /dev/disk0s2   118153176 94409664  23487512    81%    /
   my $disk_space = `df -P -k "$filesystem"`;
   chop($disk_space) if $disk_space;
   PTDEBUG && _d('Disk space on', $filesystem, $disk_space);

   return $disk_space;
}

sub check_disk_space() {
   my ($self, %args) = @_;
   my $disk_space = $args{disk_space};
   PTDEBUG && _d("Checking disk space:\n", $disk_space);

   # There may be other info, so extract just the partition line,
   # i.e. the first line starting with /, as in:
   #   Filesystem   1024-blocks     Used Available Capacity  Mounted on
   #   /dev/disk0s2   118153176 94409664  23487512    81%    /
   my ($partition) = $disk_space =~ m/^\s*(\/.+)/m;
   PTDEBUG && _d('Partition:', $partition);
   die "Failed to parse partition from disk space:\n$disk_space"
      unless $partition;

   # Parse the partition line.
   my (undef, undef, $bytes_used, $bytes_free, $pct_used, undef)
      = $partition =~ m/(\S+)/g;
   PTDEBUG && _d('Bytes used:', $bytes_used, 'free:', $bytes_free,
      'Percentage used:', $pct_used);

   # Convert 1024-blocks blocks to bytes.
   $bytes_used = ($bytes_used || 0) * 1024;
   $bytes_free = ($bytes_free || 0) * 1024;

   # Convert pct used to free.
   $pct_used =~ s/%//;
   my $pct_free = 100 - ($pct_used || 0);

   # Return true if both thresholds are ok.
   return $bytes_free >= $self->{disk_bytes_free}
       && $pct_free   >= $self->{disk_pct_free};
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
# ###########################################################################
# End Safeguards package
# ###########################################################################
