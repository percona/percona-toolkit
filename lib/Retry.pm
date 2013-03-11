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
# Retry package
# ###########################################################################
{
# Package: Retry
# Retry retries code that may die and handles those deaths nicely.
package Retry;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Time::HiRes qw(sleep);

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      %args,
   };
   return bless $self, $class;
}

# Sub: retry
#   Retry a code block that may die several times.
#
# Required Arguments:
#   try        - Callback to try.
#   fail       - Callback when try dies.
#   final_fail - Callback when try dies for the last time.
#
# Optional arguments:
#   tries  - Number of try attempts (default 3)
#   wait   - Callback after fail if tries remain (default sleep 1s)
#
# Returns:
#   Return value of try code when it doesn't die.
sub retry {
   my ( $self, %args ) = @_;
   my @required_args = qw(try fail final_fail);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my ($try, $fail, $final_fail) = @args{@required_args};
   my $wait  = $args{wait}  || sub { sleep 1; };
   my $tries = $args{tries} || 3;

   my $last_error;
   my $tryno = 0;
   TRY:
   while ( ++$tryno <= $tries ) {
      PTDEBUG && _d("Try", $tryno, "of", $tries);
      my $result;
      eval {
         $result = $try->(tryno=>$tryno);
      };
      if ( $EVAL_ERROR ) {
         PTDEBUG && _d("Try code failed:", $EVAL_ERROR);
         $last_error = $EVAL_ERROR;

         if ( $tryno < $tries ) {   # more retries
            my $retry = $fail->(tryno=>$tryno, error=>$last_error);
            last TRY unless $retry;
            PTDEBUG && _d("Calling wait code");
            $wait->(tryno=>$tryno);
         }
      }
      else {
         PTDEBUG && _d("Try code succeeded");
         return $result;
      }
   }

   PTDEBUG && _d('Try code did not succeed');
   return $final_fail->(error=>$last_error);
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
# End Retry package
# ###########################################################################
