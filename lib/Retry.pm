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
# Retry package $Revision: 7473 $
# ###########################################################################

# Package: Retry
# Retry retries code until a condition succeeds.
{
package Retry;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      %args,
   };
   return bless $self, $class;
}

# Required arguments:
#   * try          coderef: code to try; return true on success
#   * wait         coderef: code that waits in between tries
# Optional arguments:
#   * tries        scalar: number of retries to attempt (default 3)
#   * retry_on_die bool: retry try code if it dies (default no)
#   * on_success   coderef: code to call if try is successful
#   * on_failure   coderef: code to call if try does not succeed
# Retries the try code until either it returns true or we exhaust
# the number of retry attempts.  The args are passed to the coderefs
# (try, wait, on_success, on_failure).  If the try code dies, that's
# a final failure (no more retries) unless retry_on_die is true.
# Returns either whatever the try code returned or undef on failure.
sub retry {
   my ( $self, %args ) = @_;
   my @required_args = qw(try wait);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my ($try, $wait) = @args{@required_args};
   my $tries = $args{tries} || 3;

   my $tryno = 0;
   while ( ++$tryno <= $tries ) {
      MKDEBUG && _d("Retry", $tryno, "of", $tries);
      my $result;
      eval {
         $result = $try->(tryno=>$tryno);
      };

      if ( defined $result ) {
         MKDEBUG && _d("Try code succeeded");
         if ( my $on_success = $args{on_success} ) {
            MKDEBUG && _d("Calling on_success code");
            $on_success->(tryno=>$tryno, result=>$result);
         }
         return $result;
      }

      if ( $EVAL_ERROR ) {
         MKDEBUG && _d("Try code died:", $EVAL_ERROR);
         die $EVAL_ERROR unless $args{retry_on_die};
      }

      # Wait if there's more retries, else end immediately.
      if ( $tryno < $tries ) {
         MKDEBUG && _d("Try code failed, calling wait code");
         $wait->(tryno=>$tryno);
      }
   }

   MKDEBUG && _d("Try code did not succeed");
   if ( my $on_failure = $args{on_failure} ) {
      MKDEBUG && _d("Calling on_failure code");
      $on_failure->();
   }

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
# End Retry package
# ###########################################################################
