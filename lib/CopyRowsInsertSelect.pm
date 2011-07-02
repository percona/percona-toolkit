# This program is copyright 2011 Percona Inc.
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
# CopyRowsInsertSelect package $Revision: 7464 $
# ###########################################################################
{
# Package: CopyRowsInsertSelect
# CopyRowsInsertSelect implements the copy rows phase of an online schema
# change.
package CopyRowsInsertSelect;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Returns:
#   CopyRowsInsertSelect object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(Retry);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
      %args,
   };

   return bless $self, $class;
}

sub copy {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh msg from_table to_table chunks columns);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $msg, $from_table, $to_table, $chunks) = @args{@required_args};
   my $pr       = $args{Progress};
   my $sleep    = $args{sleep};
   my $columns  = join(', ', @{$args{columns}});
   my $n_chunks = @$chunks - 1;

   for my $chunkno ( 0..$n_chunks ) {
      if ( !$chunks->[$chunkno] ) {
         warn "Chunk number ", ($chunkno + 1), "is undefined";
         next;
      }

      my $sql = "INSERT IGNORE INTO $to_table ($columns) "
              . "SELECT $columns FROM $from_table "
              . "WHERE ($chunks->[$chunkno])"
              . ($args{where}        ? " AND ($args{where})"  : "")
              . ($args{engine_flags} ? " $args{engine_flags}" : "");

      # Most times we always msg($sql), but there may be a lot of chunks
      # so only do this if we're printing (i.e. not executing).
      if ( $args{print} ) {
         $msg->($sql);
      }
      else {
         MKDEBUG && _d($dbh, $sql);
         my $error;
         $self->{Retry}->retry(
            wait  => sub { sleep 1; },
            tries => 3,
            try   => sub {
               my ( %args ) = @_;
                  eval {
                     $dbh->do($sql);
                  };
                  if ( $EVAL_ERROR ) {
                     MKDEBUG && _d($EVAL_ERROR);
                     if ( $EVAL_ERROR =~ m/Lock wait timeout exceeded/ ) {
                        $error = $EVAL_ERROR;
                        if ( $args{tryno} > 1 ) {
                           $msg->("Lock wait timeout exceeded; retrying $sql");
                        }
                        return;
                     }
                     die $EVAL_ERROR;
                  }
                  return 1;
            },
            on_failure => sub { die $error; },
         );
      }

      # Update Progress (if there is one) with the chunkno just finished.
      $pr->update(sub { return $chunkno + 1; }) if $pr;

      # Sleep if there's a callback and this isn't the last chunk.
      $sleep->($chunkno + 1) if $sleep && $chunkno < $n_chunks;
   }

   return;
}

sub cleanup {
   my ( $self, %args ) = @_;
   # Nothing to cleanup, but caller is still going to call us.
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
# End CopyRowsInsertSelect package
# ###########################################################################
