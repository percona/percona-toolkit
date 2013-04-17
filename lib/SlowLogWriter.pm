# This program is copyright 2007-2011 Baron Schwartz, 2011 Percona Ireland Ltd.
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
# SlowLogWriter package
# ###########################################################################
{
# Package: SlowLogWriter
# SlowLogWriter writes events to a file in MySQL slow log format.
package SlowLogWriter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class ) = @_;
   bless {}, $class;
}

# Print out in slow-log format.
sub write {
   my ( $self, $fh, $event ) = @_;
   if ( $event->{ts} ) {
      print $fh "# Time: $event->{ts}\n";
   }
   if ( $event->{user} ) {
      printf $fh "# User\@Host: %s[%s] \@ %s []\n",
         $event->{user}, $event->{user}, $event->{host};
   }
   if ( $event->{ip} && $event->{port} ) {
      printf $fh "# Client: $event->{ip}:$event->{port}\n";
   }
   if ( $event->{Thread_id} ) {
      printf $fh "# Thread_id: $event->{Thread_id}\n";
   }

   # Tweak output according to log type: either classic or Percona-patched.
   my $percona_patched = exists $event->{QC_Hit} ? 1 : 0;

   # Classic slow log attribs.
   printf $fh
      "# Query_time: %.6f  Lock_time: %.6f  Rows_sent: %d  Rows_examined: %d\n",
      # TODO 0  Rows_affected: 0  Rows_read: 1
      map { $_ || 0 }
         @{$event}{qw(Query_time Lock_time Rows_sent Rows_examined)};

   if ( $percona_patched ) {
      # First 2 lines of Percona-patched attribs.
      printf $fh
         "# QC_Hit: %s  Full_scan: %s  Full_join: %s  Tmp_table: %s  Tmp_table_on_disk: %s\n# Filesort: %s  Filesort_on_disk: %s  Merge_passes: %d\n",
         map { $_ || 0 }
            @{$event}{qw(QC_Hit Full_scan Full_join Tmp_table Tmp_table_on_disk Filesort Filesort_on_disk Merge_passes)};

      if ( exists $event->{InnoDB_IO_r_ops} ) {
         # Optional 3 lines of Percona-patched InnoDB attribs.
         printf $fh
            "#   InnoDB_IO_r_ops: %d  InnoDB_IO_r_bytes: %d  InnoDB_IO_r_wait: %s\n#   InnoDB_rec_lock_wait: %s  InnoDB_queue_wait: %s\n#   InnoDB_pages_distinct: %d\n",
            map { $_ || 0 }
               @{$event}{qw(InnoDB_IO_r_ops InnoDB_IO_r_bytes InnoDB_IO_r_wait InnoDB_rec_lock_wait InnoDB_queue_wait InnoDB_pages_distinct)};

      } 
      else {
         printf $fh "# No InnoDB statistics available for this query\n";
      }
   }

   if ( $event->{db} ) {
      printf $fh "use %s;\n", $event->{db};
   }
   if ( $event->{arg} =~ m/^administrator command/ ) {
      print $fh '# ';
   }
   print $fh $event->{arg}, ";\n";

   return;
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
# End SlowLogWriter package
# ###########################################################################
