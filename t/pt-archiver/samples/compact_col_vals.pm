# This program is copyright 2010 Percona Inc.
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

package compact_col_vals;

# This mk-archiver plugin demonstrates how to compact a column's values.
# If a column has values {1, 3, 4, 9, 10} it is compacted to {1, 2, 3, 4, 5}
# (if $step=1).  No other column values are changed.  Column values are
# only compacted "downwards".  So if $step=2, the value above are compacted
# to {1, 3, 4, 7, 9}.
#
# This modules does *not* allow any rows to be deleted.  is_archivable()
# returns false for every row.  Even if you specify --purge, the rows will
# not be purged.  UPDATEs are made while the table is being nibbled.
# Options --dest and --file are not tested.
#
# If the compact column is AUTO_INCREMENT, you need to specify
# --no-safe-auto-incrment else the last row (i.e. the one with the highest
# auto inc value) will not be compacted.
#
# See compact_col_vals.sql for a before and after example.

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG  => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# ###########################################################################
# Customize these values for your tables.
# ###########################################################################
my $compact_column = 'id';  # column name to compact
my $step           = 1;     # amount by which column values should increase


# ###########################################################################
# Don't modify anything below here.
# ###########################################################################
sub new {
   my ( $class, %args ) = @_;
   my $o   = $args{OptionParser};
   my $q   = $args{Quoter};
   my $dbh = $args{dbh};

   my $sth;
   my $db_tbl = $q->quote($args{db}, $args{tbl});
   my $sql    = "UPDATE $db_tbl SET `$compact_column`=? "
              . "WHERE `$compact_column`=?";
   MKDEBUG && _d('sth:', $sql);
   if ( !$o->get('dry-run') ) {
      $sth = $dbh->prepare($sql);
   }
   else {
      print "# compact_col_vals plugin\n$sql\n";
   }

   my $self = {
      %args,
      db_tbl   => $db_tbl,
      sth      => $sth,
      col_pos  => undef,
      next_val => 0,
   };

   return bless $self, $class;
}

sub before_begin {
   my ( $self, %args ) = @_;
   my $allcols = $args{allcols};
   MKDEBUG && _d('allcols:', Dumper($allcols));
   my $colpos = -1;
   foreach my $col ( @$allcols ) {
      $colpos++;
      last if $col eq $compact_column;
   }
   if ( $colpos < 0 ) {
      die "Column $compact_column not selected by mk-archiver: "
         . join(', ', @$allcols);
   }
   MKDEBUG && _d('col pos:', $colpos);
   $self->{col_pos} = $colpos;
   return;
}

sub is_archivable {
   my ( $self, %args ) = @_;
   my $next_val = $self->{next_val};
   my $row      = $args{row};
   my $val      = $row->[$self->{col_pos}];
   my $sth      = $self->{sth};
   MKDEBUG && _d('val:', $val);

   if ( $next_val ){
      if ( $val > $next_val ) {
         MKDEBUG && _d('Updating', $val, 'to', $next_val);
         $sth->execute($next_val, $val); 
      }
      else {
         MKDEBUG && _d('Val is OK');
      }
   }
   else {
      # This should happen once.
      MKDEBUG && _d('First val:', $val);
      $self->{next_val} = $val;
   }

   $self->{next_val}++;
   MKDEBUG && _d('Next val should be', $self->{next_val});

   # No rows are archivable because we're exploiting mk-archiver
   # just for its ability to nibble the table.  To be safe, return 0
   # for every row so that any potential delete/purge operations
   # will not happen.
   return 0;
}

sub before_delete {
   my ( $self, %args ) = @_;
   # Because is_archivable() always returns 0, this sub should
   # not be called by mk-archiver.
   die "before_delete() was called but should not have been called!";
}

sub before_bulk_delete {
   my ( $self, %args ) = @_;
   # Because is_archivable() always returns 0, this sub should
   # not be called by mk-archiver.
   die "before_bulk_delete() was called but should not have been called!";
}

# Reset AUTO_INCREMENT to next, lowest value.
sub after_finish {
   my ( $self ) = @_;
   my $o   = $self->{OptionParser};
   my $sql = "ALTER TABLE $self->{db_tbl} AUTO_INCREMENT=$self->{next_val}";
   if ( !$o->get('dry-run') ) {
      MKDEBUG && _d($sql);
      $self->{dbh}->do($sql);
   }
   else {
      print "# compact_col_vals plugin\n$sql\n";
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
