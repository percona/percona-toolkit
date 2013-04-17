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
# IndexUsage package
# ###########################################################################
{
# Package: IndexUsage
# IndexUsage tracks index and tables usage of queries.  It can then show which
# indexes are not used.  You use it by telling it about all the tables and
# indexes that exist, and then you give it index usage stats from
# <ExplainAnalyzer>.  Afterwards, you ask it to show you unused indexes.
#
# If the object is created with a dbh and db, then results (the indexes,
# tables, queries and index usages) are saved in tables.
package IndexUsage;

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
#   IndexUsage object
sub new {
   my ( $class, %args ) = @_;
 
   my $self = {
      %args,
      tables_for      => {}, # Keyed off db
      indexes_for     => {}, # Keyed off db->tbl
      queries         => {}, # Keyed off query id
      index_usage     => {}, # Keyed off query id->db->tbl
      alt_index_usage => {}, # Keyed off query id->db->tbl->index
   };

   return bless $self, $class;
}

# Sub: add_indexes
#   Tell the object that an index exists.  Internally, it just creates usage
#   counters for the index and the table it belongs to.
#
# Parameteres:
#   %args - Arguments
#
# Required Arguments:
#   db      - Database name
#   tbl     - Table name
#   indexes - Hashref to an indexes struct returned by <TableParser::get_keys()>
sub add_indexes {
   my ( $self, %args ) = @_;
   my @required_args = qw(db tbl indexes);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($db, $tbl, $indexes) = @args{@required_args};

   $self->{tables_for}->{$db}->{$tbl}  = 0;  # usage cnt, zero until used
   $self->{indexes_for}->{$db}->{$tbl} = $indexes;
   foreach my $index ( keys %$indexes ) {
      $indexes->{$index}->{cnt} = 0;
   }

   return;
}

# Sub: add_query
#   Tell the object that a unique query (class) exists.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   query_id    - Query ID (hex checksum of fingerprint)
#   fingerprint - Query fingerprint (<QueryRewriter::fingerprint()>)
#   sample      - Query SQL
sub add_query {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id fingerprint sample);
   foreach my $arg ( @required_args  ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($query_id, $fingerprint, $sample) = @args{@required_args};

   $self->{queries}->{$query_id} = {
      fingerprint => $fingerprint,
      sample      => $sample,
   };

   return;
}

# Sub: add_table_usage
#   Increase usage count for table (even if no indexes in it are used). 
#   If saving results, the tables table is updated, too.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   db      - Database name
#   tbl     - Table name
sub add_table_usage {
   my ( $self, $db, $tbl ) = @_;
   die "I need a db and table" unless defined $db && defined $tbl;
   ++$self->{tables_for}->{$db}->{$tbl};
   return;
}

# Sub: add_index_usage
#   Save information about how a query used an index.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   usage - Uusage information, in the same format as the output from
#           <ExplainAnalyzer::get_index_usage()>
#
# Optional Arguments:
#   query_id - Query ID, if saving results; see <save_results()>
sub add_index_usage {
   my ( $self, %args ) = @_;
   my @required_args = qw(usage);
   foreach my $arg ( @required_args  ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($usage) = @args{@required_args};

   foreach my $access ( @$usage ) {
      my ($db, $tbl, $idx, $alt) = @{$access}{qw(db tbl idx alt)};
      foreach my $index ( @$idx ) {
         $self->{indexes_for}->{$db}->{$tbl}->{$index}->{cnt}++;

         # Save query/index usage if a query id was given.
         if ( my $query_id = $args{query_id} ) {
            $self->{index_usage}->{$query_id}->{$db}->{$tbl}->{$index}++;
            foreach my $alt_index ( @$alt ) {
               $self->{alt_index_usage}->{$query_id}->{$db}->{$tbl}->{$index}->{$alt_index}++;
            }
         }

      } # INDEX
   } # ACCESS

   return;
}

# Sub: find_unused_indexes
#   Find unused indexes and pass them to the callback.
#   For every table in every database, determine whether each index was used or
#   not.  But only if the table was used.  Don't say "this index should be
#   dropped" if the table was never queried.  For each table, collect the unused
#   indexes and execute the callback subroutine with a hashref that looks like
#   this:
#   (start code)
#   { db => db, tbl => tbl, idx => [<list of unused indexes on this table>] }
#   (end code)
#
# Parameters:
#   $callback - Coderef called with unused indexes
sub find_unused_indexes {
   my ( $self, $callback ) = @_;
   die "I need a callback" unless $callback;
   PTDEBUG && _d("Finding unused indexes");

   DATABASE:
   foreach my $db ( sort keys %{$self->{indexes_for}} ) {
      TABLE:
      foreach my $tbl ( sort keys %{$self->{indexes_for}->{$db}} ) {
         next TABLE unless $self->{tables_for}->{$db}->{$tbl}; # Skip unused
         my $indexes = $self->{indexes_for}->{$db}->{$tbl};
         my @unused_indexes;
         foreach my $index ( sort keys %$indexes ) {
            if ( !$indexes->{$index}->{cnt} ) { # count of times accessed/used
               push @unused_indexes, $indexes->{$index};
            }
         }

         if ( @unused_indexes ) {
            $callback->(
               {  db  => $db,
                  tbl => $tbl,
                  idx => \@unused_indexes,
               }
            );
         }
      } # TABLE
   } # DATABASE

   return;
}

# Sub: save_results
#   Save all the table, index and query usage information to tables.
#   This sub should only be called once!  If it's called a second time,
#   the cnt columns will be updated with their current val + this object's
#   cnt value because of "ON DUPLICATE KEY UPDATE cnt = cnt + ?".  This
#   is required so that the tool can be ran multiple times, updating
#   saved result counts each time.  Thus, the tool should only call this
#   sub once.  Then it needs to create a new IndexUsage object (unless
#   we implement a reset() sub).
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dbh - DBH
#   db  - Database where mk-index-usage --save-results tables are located
sub save_results {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db);
   foreach my $arg ( @required_args  ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($dbh, $db) = @args{@required_args};
   PTDEBUG && _d("Saving results to tables in database", $db);

   PTDEBUG && _d("Saving index data");
   my $insert_index_sth = $dbh->prepare(
      "INSERT INTO `$db`.`indexes` (db, tbl, idx, cnt) VALUES (?, ?, ?, ?) "
      . "ON DUPLICATE KEY UPDATE cnt = cnt + ?");
   foreach my $db ( keys %{$self->{indexes_for}} ) {
      foreach my $tbl ( keys %{$self->{indexes_for}->{$db}} ) {
         foreach my $index ( keys %{$self->{indexes_for}->{$db}->{$tbl}} ) {
            my $cnt = $self->{indexes_for}->{$db}->{$tbl}->{$index}->{cnt};
            $insert_index_sth->execute($db, $tbl, $index, $cnt, $cnt);
         }
      }
   }

   PTDEBUG && _d("Saving table data");
   my $insert_tbl_sth = $dbh->prepare(
      "INSERT INTO `$db`.`tables` (db, tbl, cnt) VALUES (?, ?, ?) "
      . "ON DUPLICATE KEY UPDATE cnt = cnt + ?");
   foreach my $db ( keys %{$self->{tables_for}} ) {
      foreach my $tbl ( keys %{$self->{tables_for}->{$db}} ) {
         my $cnt = $self->{tables_for}->{$db}->{$tbl};
         $insert_tbl_sth->execute($db, $tbl, $cnt, $cnt);
      }
   }

   PTDEBUG && _d("Save query data");
   my $insert_query_sth = $dbh->prepare(
      "INSERT IGNORE INTO `$db`.`queries` (query_id, fingerprint, sample) "
      . " VALUES (CONV(?, 16, 10), ?, ?)");
   foreach my $query_id ( keys %{$self->{queries}} ) {
      my $query = $self->{queries}->{$query_id};
      $insert_query_sth->execute(
         $query_id, $query->{fingerprint}, $query->{sample});
   }

   PTDEBUG && _d("Saving index usage data");
   my $insert_index_usage_sth = $dbh->prepare(
      "INSERT INTO `$db`.`index_usage` (query_id, db, tbl, idx, cnt) "
      . "VALUES (CONV(?, 16, 10), ?, ?, ?, ?) "
      . "ON DUPLICATE KEY UPDATE cnt = cnt + ?");
   foreach my $query_id ( keys %{$self->{index_usage}} ) {
      foreach my $db ( keys %{$self->{index_usage}->{$query_id}} ) {
         foreach my $tbl ( keys %{$self->{index_usage}->{$query_id}->{$db}} ) {
            my $indexes = $self->{index_usage}->{$query_id}->{$db}->{$tbl};
            foreach my $index ( keys %$indexes ) {
               my $cnt = $indexes->{$index};
               $insert_index_usage_sth->execute(
                  $query_id, $db, $tbl, $index, $cnt, $cnt);
            }
         }
      }
   }

   PTDEBUG && _d("Saving alternate index usage data");
   my $insert_index_alt_sth = $dbh->prepare(
      "INSERT INTO `$db`.`index_alternatives` "
      . "(query_id, db, tbl, idx, alt_idx, cnt) "
      . "VALUES (CONV(?, 16, 10), ?, ?, ?, ?, ?) "
      . "ON DUPLICATE KEY UPDATE cnt = cnt + ?");
   foreach my $query_id ( keys %{$self->{alt_index_usage}} ) {
      foreach my $db ( keys %{$self->{alt_index_usage}->{$query_id}} ) {
         foreach my $tbl ( keys %{$self->{alt_index_usage}->{$query_id}->{$db}} ) {
            foreach my $index ( keys %{$self->{alt_index_usage}->{$query_id}->{$db}->{$tbl}} ){
               my $alt_indexes = $self->{alt_index_usage}->{$query_id}->{$db}->{$tbl}->{$index};
               foreach my $alt_index ( keys %$alt_indexes ) {
                  my $cnt = $alt_indexes->{$alt_index};
                  $insert_index_alt_sth->execute(
                     $query_id, $db, $tbl, $index, $alt_index, $cnt, $cnt);
               }
            }
         }
      }
   }

   $dbh->commit unless $dbh->{AutoCommit};
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
# End IndexUsage package
# ###########################################################################
