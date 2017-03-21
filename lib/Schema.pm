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
# Schema package
# ###########################################################################
{
# Package: Schema
# Schema encapsulates a data structure representing databases and tables.
# Although in MySQL "schema" is technically equivalent to "databae", we
# use "schema" loosely to mean a collection of schema objects: databases,
# tables, and columns.  These objects are organized in a hash keyed on
# database and table names.  The hash is called schema and looks like,
# (start code)
#   db1 => {
#      tbl1 => {
#         db         => 'db1',
#         tbl        => 'tbl1',
#         tbl_struct => <TableParser::parse()>
#         ddl        => "CREATE TABLE `tbl` ( ...",
#      }
#   }
# (stop code)
# Each table has at least a db and tbl key and probably a tbl_struct.
#
# The important thing about a Schema object is that it should be the only
# data structure with this data, and other modules should reference and add
# data to it rather than creating other similar copies.  <ColumnMap> does
# this for example.
#
# The other important thing about a Schema object is that the data structure
# is the standard.  Other modules should take db or tbl hashrefs pointing
# into the data structure.  Tbl hashrefs should always have at least at db
# and tbl key (which is redundant but necessary so that each tbl hashref
# includes its own database and table name).
#
# Schema objects are usually added by a <SchemaIterator>, but you can add
# them manually if needed; see <add_schema_object()>.
package Schema;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Returns:
#  Schema object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
      %args,
      schema  => {},  # keyed on db->tbl
      # columns => {},  # No tools use is_duplicate_table() or
      # tables  => {},  # is_duplicate_column() yet...
   };
   return bless $self, $class;
}

sub get_schema {
   my ( $self ) = @_;
   return $self->{schema};
}

sub get_table {
   my ( $self, $db_name, $tbl_name ) = @_;
   if ( exists $self->{schema}->{$db_name}
        && exists $self->{schema}->{$db_name}->{$tbl_name} ) {
      return $self->{schema}->{$db_name}->{$tbl_name};
   }
   return;
}

#sub is_duplicate_column {
#   my ( $self, $col ) = @_;
#   return unless $col;
#   return ($self->{columns}->{$col} || 0) > 1 ? 1 : 0;
#}

#sub is_duplicate_table {
#   my ( $self, $tbl ) = @_;
#   return unless $tbl;
#   return ($self->{tables}->{$tbl} || 0) > 1 ? 1 : 0;
#}

# Sub: add_schema_object
#   Add a schema object.  This sub is called by
#   <SchemaIterator::next_schema_object()>.
#
# Parameters:
#   $schema_object - Schema object hashref.
sub add_schema_object {
   my ( $self, $schema_object ) = @_;
   die "I need a schema_object argument" unless $schema_object;

   my ($db, $tbl) = @{$schema_object}{qw(db tbl)};
   if ( !$db || !$tbl ) {
      warn "No database or table for schema object";
      return;
   }

   my $tbl_struct = $schema_object->{tbl_struct};
   if ( !$tbl_struct ) {
      warn "No table structure for $db.$tbl";
      return;
   }

   # Add/save this schema object.
   $self->{schema}->{lc $db}->{lc $tbl} = $schema_object;

   # Get duplicate column and table names.
   # map { $self->{columns}->{lc $_}++ } @{$tbl_struct->{cols}};
   # $self->{tables}->{lc $tbl_struct->{name}}++;

   return;
}

sub find_column {
   my ( $self, %args ) = @_;
   my $ignore = $args{ignore};
   my $schema = $self->{schema};

   my ($col, $tbl, $db);
   if ( my $col_name = $args{col_name} ) {
      ($col, $tbl, $db) = reverse map { s/`//g; $_ } split /[.]/, $col_name;
      PTDEBUG && _d('Column', $col_name, 'has db', $db, 'tbl', $tbl,
         'col', $col);
   }
   else {
      ($col, $tbl, $db) = @args{qw(col tbl db)};
   }

   $db  = lc($db  || '');
   $tbl = lc($tbl || '');
   $col = lc($col || '');

   if ( !$col ) {
      PTDEBUG && _d('No column specified or parsed');
      return;
   }
   PTDEBUG && _d('Finding column', $col, 'in', $db, $tbl);

   if ( $db && !$schema->{$db} ) {
      PTDEBUG && _d('Database', $db, 'does not exist');
      return;
   }

   if ( $db && $tbl && !$schema->{$db}->{$tbl} ) {
      PTDEBUG && _d('Table', $tbl, 'does not exist in database', $db);
      return;
   }

   my @tbls;
   my @search_dbs = $db ? ($db) : keys %$schema;
   DATABASE:
   foreach my $search_db ( @search_dbs ) {
      my @search_tbls = $tbl ? ($tbl) : keys %{$schema->{$search_db}};

      TABLE:
      foreach my $search_tbl ( @search_tbls ) {
         next DATABASE unless exists $schema->{$search_db}->{$search_tbl};

         if ( $ignore
              && grep { $_->{db} eq $search_db && $_->{tbl} eq $search_tbl }
                 @$ignore ) {
            PTDEBUG && _d('Ignoring', $search_db, $search_tbl, $col);
            next TABLE;
         }

         my $tbl = $schema->{$search_db}->{$search_tbl};
         if ( $tbl->{tbl_struct}->{is_col}->{$col} ) {
            PTDEBUG && _d('Column', $col, 'exists in', $tbl->{db}, $tbl->{tbl});
            push @tbls, $tbl;
         }
      }
   }

   @tbls = sort {$b->{name} cmp $a->{name}} @tbls;
   return \@tbls;

}

sub find_table {
   my ( $self, %args ) = @_;
   my $ignore = $args{ignore};
   my $schema = $self->{schema};

   my ($tbl, $db);
   if ( my $tbl_name = $args{tbl_name} ) {
      ($tbl, $db) = reverse map { s/`//g; $_ } split /[.]/, $tbl_name;
      PTDEBUG && _d('Table', $tbl_name, 'has db', $db, 'tbl', $tbl);
   }
   else {
      ($tbl, $db) = @args{qw(tbl db)};
   }

   $db  = lc($db  || '');
   $tbl = lc($tbl || '');

   if ( !$tbl ) {
      PTDEBUG && _d('No table specified or parsed');
      return;
   }
   PTDEBUG && _d('Finding table', $tbl, 'in', $db);

   if ( $db && !$schema->{$db} ) {
      PTDEBUG && _d('Database', $db, 'does not exist');
      return;
   }

   if ( $db && $tbl && !$schema->{$db}->{$tbl} ) {
      PTDEBUG && _d('Table', $tbl, 'does not exist in database', $db);
      return;
   }

   my @dbs;
   my @search_dbs = $db ? ($db) : keys %$schema;
   DATABASE:
   foreach my $search_db ( @search_dbs ) {
      if ( $ignore && grep { $_->{db} eq $search_db } @$ignore ) {
         PTDEBUG && _d('Ignoring', $search_db);
         next DATABASE;
      }

      if ( exists $schema->{$search_db}->{$tbl} ) {
         PTDEBUG && _d('Table', $tbl, 'exists in', $search_db);
         push @dbs, $search_db;
      }
   }

   @dbs = sort @dbs;
   return \@dbs;
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
# End Schema package
# ###########################################################################
