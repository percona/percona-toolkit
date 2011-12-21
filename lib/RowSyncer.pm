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
# RowSyncer package
# ###########################################################################
{
# Package: RowSyncer
# RowSyncer syncs a destination row to a source row.
package RowSyncer;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = {
      crc_col => 'crc',
      %args,
   };
   return bless $self, $class;
}

sub set_crc_col {
   my ($self, $crc_col) = @_;
   $self->{crc_col} = $crc_col;
   return;
}

sub set_key_cols {
   my ($self, $key_cols) = @_;
   $self->{key_cols} = $key_cols;
   return;
}

sub key_cols {
   my ($self) = @_;
   return $self->{key_cols};
}

sub same_row {
   my ($self, %args) = @_;
   my ($lr, $rr) = @args{qw(lr rr)};
   if ( $lr->{$self->{crc_col}} ne $rr->{$self->{crc_col}} ) {
      $self->{ChangeHandler}->change('UPDATE', $lr, $self->key_cols());
   }
   return;
}

sub not_in_right {
   my ( $self, %args ) = @_;
   # Row isn't in the dest, re-insert it in the source.
   $self->{ChangeHandler}->change('INSERT', $args{lr}, $self->key_cols());
   return;
}

sub not_in_left {
   my ( $self, %args ) = @_;
   # Row isn't in source, delete it from the dest.
   $self->{ChangeHandler}->change('DELETE', $args{rr}, $self->key_cols());
   return;
}

sub done_with_rows {
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
# End RowSyncer package
# ###########################################################################
