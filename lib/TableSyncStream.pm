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
# TableSyncStream package
# ###########################################################################
{
# Package: TableSyncStream
# TableSyncStream is a table sync algo that selects all rows.
# This package implements the simplest possible table-sync algorithm:
# read every row from the tables and compare them.
package TableSyncStream;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(Quoter) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub name {
   return 'Stream';
}

sub can_sync {
   return 1;  # We can sync anything.
}

sub prepare_to_sync {
   my ( $self, %args ) = @_;
   my @required_args = qw(cols ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   $self->{cols}            = $args{cols};
   $self->{buffer_in_mysql} = $args{buffer_in_mysql};
   $self->{ChangeHandler}   = $args{ChangeHandler};

   $self->{done}  = 0;

   return;
}

sub uses_checksum {
   return 0;  # We don't need checksum queries.
}

sub set_checksum_queries {
   return;  # This shouldn't be called, but just in case.
}

sub prepare_sync_cycle {
   my ( $self, $host ) = @_;
   return;
}

sub get_sql {
   my ( $self, %args ) = @_;
   return "SELECT "
      . ($self->{buffer_in_mysql} ? 'SQL_BUFFER_RESULT ' : '')
      . join(', ', map { $self->{Quoter}->quote($_) } @{$self->{cols}})
      . ' FROM ' . $self->{Quoter}->quote(@args{qw(database table)})
      . ' WHERE ' . ( $args{where} || '1=1' );
}

sub same_row {
   my ( $self, %args ) = @_;
   return;
}

sub not_in_right {
   my ( $self, %args ) = @_;
   $self->{ChangeHandler}->change('INSERT', $args{lr}, $self->key_cols());
}

sub not_in_left {
   my ( $self, %args ) = @_;
   $self->{ChangeHandler}->change('DELETE', $args{rr}, $self->key_cols());
}

sub done_with_rows {
   my ( $self ) = @_;
   $self->{done} = 1;
}

sub done {
   my ( $self ) = @_;
   return $self->{done};
}

sub key_cols {
   my ( $self ) = @_;
   return $self->{cols};
}

# Return 1 if you have changes yet to make and you don't want the TableSyncer to
# commit your transaction or release your locks.
sub pending_changes {
   my ( $self ) = @_;
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
# End TableSyncStream package
# ###########################################################################
