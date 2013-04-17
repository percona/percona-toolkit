# This program is copyright 2011 Percona Ireland Ltd.
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
# CleanupTask package
# ###########################################################################
{
# Package: CleanupTask
# CleanupTask does something when the object is destroyed.  This is used,
# for example, to close all dbh gracefully when a program dies unexpectedly.
package CleanupTask;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Sub: new
#
# Parameters:
#   task - Callback executed when object is destroyed
#
# Returns:
#   CleanupTask object
sub new {
   my ( $class, $task ) = @_;
   die "I need a task parameter" unless $task;
   die "The task parameter must be a coderef" unless ref $task eq 'CODE';
   my $self = {
      task => $task,
   };
   open $self->{stdout_copy}, ">&=", *STDOUT
      or die "Cannot dup stdout: $OS_ERROR";
   open $self->{stderr_copy}, ">&=", *STDERR
      or die "Cannot dup stderr: $OS_ERROR";
   PTDEBUG && _d('Created cleanup task', $task);
   return bless $self, $class;
}

sub DESTROY {
   my ($self) = @_;
   my $task = $self->{task};
   if ( ref $task ) {
      PTDEBUG && _d('Calling cleanup task', $task);
      # Temporarily restore STDOUT and STDERR to what they were
      # when the object was created
      open local(*STDOUT), ">&=", $self->{stdout_copy}
         if $self->{stdout_copy};
      open local(*STDERR), ">&=", $self->{stderr_copy}
         if $self->{stderr_copy};
      $task->();
   }
   else {
      warn "Lost cleanup task";
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
# End CleanupTask package
# ###########################################################################
