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

package delete_more;

# This mk-archiver plugin demonstrates how to archive/DELETE rows on one
# table--the main table--and also DELETE related rows on other tables.
# The picture is:
#
#   main_table-123:  other_table-123:
#     col-m 1           col-o 1
#     col-m 2           col-o 1
#                       col-o 2
#
# When rows on main table are deleted, corresponding rows on the other
# tables are deleted where main table col-m = other table col-o.  This
# works for both single and --bulk-delete.  The tables are *not* 1-to-1
# so a single delete for main col-m = 1 will result in two deletes fro
# other col-o = 1.  This means --limit does *not* apply on other table.
# 
# The other table's name is derived from the main table's name according
# to the settings below.
#
# Limitations:
#   * all tables must be on the same server
#   * other table column (e.g. opk) must be the same on all other tables
#   * main table column and other table columns must be numeric
#   * no NULL values

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG  => $ENV{MKDEBUG};

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# ###########################################################################
# Customize these values for your tables.
# ###########################################################################
my $main_table_col   = 'id';   # main table pk col
my $other_table_col  = 'id';   # other table pk col
my $main_table_id    = qr/(\d+)$/;
my $other_table_base = 'other_table-';
my $other_db         = undef;  # undef = same as main db
my $other_table      = undef;  # undef = auto-determine

# ###########################################################################
# Don't modify anything below here.
# ###########################################################################
sub new {
   my ( $class, %args ) = @_;
   my $o = $args{OptionParser};
   my $q = $args{Quoter};

   $other_db ||= $args{db};

   if ( !$other_table ) {
      my ($id) = $args{tbl} =~ m/$main_table_id/;
      die "Cannot determine other table; $args{tbl} does not match "
         . $main_table_id unless $id;
      $other_table = $other_table_base . $id;
   }
   $other_table = $q->quote($other_db, $other_table);
   MKDEBUG && _d('Other table:', $other_table);

   my $self = {
      dbh          => $args{dbh},
      bulk_delete  => $o->get('bulk-delete'),
      limit        => $o->get('limit'),
      delete_rows  => [],  # saved main table col vals for --bulk-delete
      main_col_pos => -1,
      other_tbl    => $other_table,
   };

   if ( $o->get('dry-run') ) {
      print "# delete_more other table $other_table\n";
   }

   return bless $self, $class;
}

sub before_begin {
   my ( $self, %args ) = @_;
   my $allcols = $args{allcols};
   MKDEBUG && _d('allcols:', Dumper($allcols));
   my $colpos = -1;
   foreach my $col ( @$allcols ) {
      $colpos++;
      last if $col eq $main_table_col;
   }
   if ( $colpos < 0 ) {
      die "Main table column $main_table_col not selected by mk-archiver: "
         . join(', ', @$allcols);
   }
   MKDEBUG && _d('main col pos:', $colpos);
   $self->{main_col_pos} = $colpos;
   return;
}

sub is_archivable {
   my ( $self, %args ) = @_;
   my $row = $args{row};
   push @{$self->{delete_rows}}, $row->[$self->{main_col_pos}]
      if $self->{bulk_delete};
   return 1;
}

sub before_delete {
   my ( $self, %args ) = @_;
   my $row = $args{row};
   my $val = $row->[ $self->{main_col_pos} ];
   my $dbh = $self->{dbh};

   my $sql = "DELETE FROM $self->{other_tbl} "
           . "WHERE $other_table_col=$val";
   MKDEBUG && _d($sql);
   eval {
      $dbh->do($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
      warn $EVAL_ERROR;
   }

   return;
}

sub before_bulk_delete {
   my ( $self, %args ) = @_;

   if ( !scalar @{$self->{delete_rows}} ) {
      warn "before_bulk_delete() called without any rows to delete";
      return;
   }

   my $dbh              = $self->{dbh};
   my $delete_rows      = join(',', @{$self->{delete_rows}});
   $self->{delete_rows} = [];  # clear for next call


   my $sql = "DELETE FROM $self->{other_tbl} "
           . "WHERE $other_table_col IN ($delete_rows) ";
#           . "LIMIT $self->{limit}";
   MKDEBUG && _d($sql);
   eval {
      $dbh->do($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
      warn $EVAL_ERROR;
   }

   return;
}

sub after_finish {
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
