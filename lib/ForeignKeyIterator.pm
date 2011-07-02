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
# ForeignKeyIterator package $Revision: 7552 $
# ###########################################################################
{
# Package: ForeignKeyIterator
# ForeignKeyIterator iterates from or to a table by its foreign key constraints.
# This is a special type of <SchemaIterator> with the same interface, so it
# can be used in place of a <SchemaIterator>, but internally it functions
# very differently.  Whereas a <SchemaIterator> is a real iterator that only
# gets the next schema object when called, a ForeignKeyIterator slurps the
# given <SchemaIterator> so it can discover foreign key constraints.
package ForeignKeyIterator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   db             - Database of tbl.
#   tbl            - Table to iterate from to its referenced tables.
#   Schema         - <Schema> object.
#   SchemaIterator - <SchemaIterator> object created with Schema and
#                    keep_ddl=>true.
#   TableParser    - <TableParser> object.
#   Quoter         - <Quoter> object.
#
# Optional Arguments:
#   reverse - Iterate in reverse, from referenced tables to tbl.
#
# Returns:
#   ForeignKeyIterator object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(db tbl Schema SchemaIterator TableParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   MKDEBUG && _d('Reverse iteration:', $args{reverse} ? 'yes' : 'no');
   my $self = {
      %args,
   };

   return bless $self, $class;
}

# Sub: next_schema_object
#   Return the next schema object or undef when no more schema objects.
#
# Returns:
#   Hashref of schema object with at least a db and tbl keys, like
#   (start code)
#   {
#      db         => 'test',
#      tbl        => 'a',
#      ddl        => 'CREATE TABLE `a` ( ...',
#      tbl_struct => <TableParser::parse()> hashref of parsed ddl,
#      fk_struct  => <TableParser::get_fks()> hashref of parsed fk constraints
#   }
#   (end code)
sub next_schema_object {
   my ( $self ) = @_;

   if ( !exists $self->{fk_refs} ) {
      # The default code order is (childN, child1, parent), but the default
      # user order is (parent, child1, childN).  So the two are opposite.
      # Thus for default user order we reverse code order, and for reverse
      # user order we keep the default code order.  Yes, it's a confusing
      # double negative, but it can't be avoided.
      my @fk_refs = $self->_get_fk_refs();
      @fk_refs = reverse @fk_refs if !$self->{reverse};
      MKDEBUG && _d("Foreign key table order:\n",
         map { "$_->{db}.$_->{tbl}\n" } @fk_refs);

      # Save the originals and then create a copy of them to return
      # when called.  If reset, then copy originals back to fk_refs.
      $self->{original_fk_refs} = \@fk_refs;
      $self->{fk_refs}          = [@fk_refs]; # copy
   }

   my $schema_obj = shift @{$self->{fk_refs}};
   MKDEBUG && _d('Next schema object:', $schema_obj->{db}, $schema_obj->{tbl});
   return $schema_obj;
}

sub reset {
   my ( $self ) = @_;
   $self->{fk_refs} = [ @{$self->{original_fk_refs}} ]; # copy
   MKDEBUG && _d('ForeignKeyIterator reset');
   return;
}

sub _get_fk_refs {
   my ( $self ) = @_;
   my $schema_itr = $self->{SchemaIterator};
   my $tp         = $self->{TableParser};
   my $q          = $self->{Quoter};
   MKDEBUG && _d('Loading schema from SchemaIterator');

   # First we need to load all schema objects from the iterator and
   # parse any foreign key constraints.
   SCHEMA_OBJECT:
   while ( my $obj = $schema_itr->next_schema_object() ) {
      my ($db, $tbl) = @{$obj}{qw(db tbl)};

      if ( !$db || !$tbl ) {
         die "No database or table name for schema object";
      }

      if ( !$obj->{ddl} ) {
         # If the SchemaIterator obj was created with a dbh, this probably
         # means that it was not also created with a MySQLDump obj.
         die "No CREATE TABLE for $db.$tbl";
      }

      if ( !$obj->{tbl_struct} ) {
         # This probably means that the SchemaIterator obj wasn't created
         # with a TableParser obj.
         die "No table structure for $db.$tbl";
      }

      my $fks = $tp->get_fks($obj->{ddl}, { database => $db });
      if ( $fks && scalar values %$fks ) {
         MKDEBUG && _d('Table', $db, $tbl, 'has foreign keys');
         $obj->{fk_struct} = $fks;
         foreach my $fk ( values %$fks ) {
            my ($parent_db, $parent_tbl) = @{$fk->{parent_tbl}}{qw(db tbl)};
            if ( !$parent_db ) {
               MKDEBUG && _d('No fk parent table database,',
                  'assuming child table database', $tbl->{db});
               $parent_db = $tbl->{db};
            }
            push @{$obj->{references}}, [$parent_db, $parent_tbl];
         }
      }
   }

   # Now we can recurse through the foreign key references, starting with
   # the target db.tbl.
   return $self->_recurse_fk_references(
      $self->{Schema}->get_schema(),
      $self->{db},
      $self->{tbl},
   );
}

sub _recurse_fk_references {
   my ( $self, $schema, $db, $tbl, $seen ) = @_;
   $seen ||= {};

   if ( $seen && $seen->{"$db$tbl"}++ ) {
      MKDEBUG && _d('Circular reference, already seen', $db, $tbl);
      return;
   }
   MKDEBUG && _d('Recursing from', $db, $tbl);

   my @fk_refs;
   if ( $schema->{$db}->{$tbl}->{references} ) {
      foreach my $refed_obj ( @{$schema->{$db}->{$tbl}->{references}} ) {
         MKDEBUG && _d($db, $tbl, 'references', @$refed_obj);
         push @fk_refs,
            $self->_recurse_fk_references($schema, @$refed_obj, $seen);
      }
   }

   MKDEBUG && _d('No more tables referenced by', $db, $tbl);
   push @fk_refs, $schema->{$db}->{$tbl};

   return @fk_refs;
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
# End ForeignKeyIterator package
# ###########################################################################
