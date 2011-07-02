# This program is copyright 2008-2011 Percona Inc.
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
# ProcesslistAggregator package $Revision: 6590 $
# ###########################################################################
{
# Package: ProcesslistAggregator
# ProcesslistAggregator aggregates PROCESSLIST entires.
package ProcesslistAggregator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      undef_val => $args{undef_val} || 'NULL',
   };
   return bless $self, $class;
}

# Given an arrayref of processes ($proclist), returns an hashref of
# time and counts aggregates for User, Host, db, Command and State.
# See t/ProcesslistAggregator.t for examples.
# The $proclist arg is usually the return val of:
#    $dbh->selectall_arrayref('SHOW PROCESSLIST', { Slice => {} } );
sub aggregate {
   my ( $self, $proclist ) = @_;
   my $aggregate = {};
   foreach my $proc ( @{$proclist} ) {
      foreach my $field ( keys %{ $proc } ) {
         # Don't aggregate these fields.
         next if $field eq 'Id';
         next if $field eq 'Info';
         next if $field eq 'Time';

         # Format the field's value a little.
         my $val  = $proc->{ $field };
            $val  = $self->{undef_val} if !defined $val;
            $val  = lc $val if ( $field eq 'Command' || $field eq 'State' );
            $val  =~ s/:.*// if $field eq 'Host';

         my $time = $proc->{Time};
            $time = 0 if !$time || $time eq 'NULL';

         # Do this last or else $proc->{$field} won't match.
         $field = lc $field;

         $aggregate->{ $field }->{ $val }->{time}  += $time;
         $aggregate->{ $field }->{ $val }->{count} += 1;
      }
   }
   return $aggregate;
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
# End ProcesslistAggregator package
# ###########################################################################
