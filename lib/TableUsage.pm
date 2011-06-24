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
# TableUsage package $Revision: 7498 $
# ###########################################################################

# Package: TableUsage
# TableUsage determines how tables in a query are used.
#
# For best results, queries should be from EXPLAIN EXTENDED so all identifiers
# are fully qualified.  Else, some table references may be missed because
# no effort is made to table-qualify unqualified columns.
#
# This package uses both QueryParser and SQLParser.  The former is used for
# simple queries, and the latter is used for more complex queries where table
# usage may be hidden in who-knows-which clause of the SQL statement.
{
package TableUsage;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   QueryParser - <QueryParser> object
#   SQLParser   - <SQLParser> object
#
# Optional Arguments:
#   constant_data_value - Value for constants, default "DUAL".
#
# Returns:
#   TableUsage object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(QueryParser SQLParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
      # defaults
      constant_data_value => 'DUAL',

      # override defaults
      %args,
   };

   return bless $self, $class;
}

# Sub: get_table_usage
#   Get table usage for each table in the given query.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   query - Query string
#
# Returns:
#   Arrayref of hashrefs, one for each CAT, like:
#   (code start)
#   [
#     { context => 'DELETE',
#       table   => 'd.t',
#     },
#     { context => 'DELETE',
#       table   => 'd.t',
#     },
#   ],
#   (code stop)
sub get_table_usage {
   my ( $self, %args ) = @_;
   my @required_args = qw(query);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($query)   = @args{@required_args};
   MKDEBUG && _d('Getting table access for',
      substr($query, 0, 100), (length $query > 100 ? '...' : ''));

   my $cats;  # arrayref of CAT hashrefs for each table

   # Try to parse the query first with SQLParser.  This may be overkill for
   # simple queries, but it's probably cheaper to just do this than to try
   # detect first if the query is simple enough to parse with QueryParser.
   my $query_struct;
   eval {
      $query_struct = $self->{SQLParser}->parse($query);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d('Failed to parse query with SQLParser:', $EVAL_ERROR);
      if ( $EVAL_ERROR =~ m/Cannot parse/ ) {
         # SQLParser can't parse this type of query, so it's probably some
         # data definition statement with just a table list.  Use QueryParser
         # to extract the table list and hope we're not wrong.
         $cats = $self->_get_tables_used_from_query_parser(%args);
      }
      else {
         # SQLParser failed to parse the query due to some error.
         die $EVAL_ERROR;
      }
   }
   else {
      # SQLParser parsed the query, so now we need to examine its structure
      # to determine the CATs for each table.
      $cats = $self->_get_tables_used_from_query_struct(
         query_struct => $query_struct,
         %args,
      );
   }

   MKDEBUG && _d('Query table access:', Dumper($cats));
   return $cats;
}

sub _get_tables_used_from_query_parser {
   my ( $self, %args ) = @_;
   my @required_args = qw(query);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($query) = @args{@required_args};
   MKDEBUG && _d('Getting tables used from query parser');

   $query = $self->{QueryParser}->clean_query($query);
   my ($query_type) = $query =~ m/^\s*(\w+)\s+/;
   $query_type = uc $query_type;
   die "Query does not begin with a word" unless $query_type; # shouldn't happen

   if ( $query_type eq 'DROP' ) {
      my ($drop_what) = $query =~ m/^\s*DROP\s+(\w+)\s+/i;
      die "Invalid DROP query: $query" unless $drop_what;
      # Don't use a space like "DROP TABLE" because the output of
      # mk-table-usage is space-separated.
      $query_type .= '_' . uc($drop_what);
   }

   my @tables_used;
   foreach my $table ( $self->{QueryParser}->get_tables($query) ) {
      $table =~ s/`//g;
      push @{$tables_used[0]}, {
         table   => $table,
         context => $query_type,
      };
   }

   return \@tables_used;
}

sub _get_tables_used_from_query_struct {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($query_struct) = @args{@required_args};
   my $sp             = $self->{SQLParser};

   MKDEBUG && _d('Getting table used from query struct');

   # The table references clause is different depending on the query type.
   my $query_type = uc $query_struct->{type};
   my $tbl_refs   = $query_type =~ m/(?:SELECT|DELETE)/  ? 'from'
                  : $query_type =~ m/(?:INSERT|REPLACE)/ ? 'into'
                  : $query_type =~ m/UPDATE/             ? 'tables'
                  : die "Cannot find table references for $query_type queries";
   my $tables     = $query_struct->{$tbl_refs};

   if ( !$tables || @$tables == 0 ) {
      MKDEBUG && _d("Query does not use any tables");
      return [
         [ { context => $query_type, table => $self->{constant_data_value} } ]
      ];
   }

   # Get tables used in the query's WHERE clause, if it has one.
   my $where;
   if ( $query_struct->{where} ) {
      $where = $self->_get_tables_used_in_where(
         %args,
         tables  => $tables,
         where   => $query_struct->{where},
      );
   }

   my @tables_used;
   if ( $query_type eq 'UPDATE' && @{$query_struct->{tables}} > 1 ) {
      MKDEBUG && _d("Multi-table UPDATE");
      # UPDATE queries with multiple tables are a special case.  The query
      # reads from each referenced table and writes only to tables referenced
      # in the SET clause.  Each written table is like its own query, so
      # we create a table usage hashref for each one.

      my @join_tables;
      foreach my $table ( @$tables ) {
         my $table = $self->_qualify_table_name(
            %args,
            tables => $tables,
            db     => $table->{db},
            tbl    => $table->{tbl},
         );
         my $table_usage = {
            context => 'JOIN',
            table   => $table,
         };
         MKDEBUG && _d("Table usage from TLIST:", Dumper($table_usage));
         push @join_tables, $table_usage;
      }
      if ( $where && $where->{joined_tables} ) {
         foreach my $table ( @{$where->{joined_tables}} ) {
            my $table_usage = {
               context => $query_type,
               table   => $table,
            };
            MKDEBUG && _d("Table usage from WHERE (implicit join):",
               Dumper($table_usage));
            push @join_tables, $table_usage;
         }
      }

      my @where_tables;
      if ( $where && $where->{filter_tables} ) {
         foreach my $table ( @{$where->{filter_tables}} ) {
            my $table_usage = {
               context => 'WHERE',
               table   => $table,
            };
            MKDEBUG && _d("Table usage from WHERE:", Dumper($table_usage));
            push @where_tables, $table_usage;
         }
      }

      my $set_tables = $self->_get_tables_used_in_set(
         %args,
         tables  => $tables,
         set     => $query_struct->{set},
      );
      foreach my $table ( @$set_tables ) {
         my @table_usage = (
            {  # the written table
               context => 'UPDATE',
               table   => $table->{table},
            },
            {  # source of data written to the written table
               context => 'SELECT',
               table   => $table->{value},
            },
         );
         MKDEBUG && _d("Table usage from UPDATE SET:", Dumper(\@table_usage));
         push @tables_used, [
            @table_usage,
            @join_tables,
            @where_tables,
         ];
      }
   } # multi-table UPDATE
   else {
      # Only data in tables referenced in the column list are returned
      # to the user.  So a table can appear in the tlist (e.g. after FROM)
      # but that doesn't mean data from the table is returned to the user;
      # the table could be used purely for JOIN or WHERE.
      if ( $query_type eq 'SELECT' ) {
         my $clist_tables = $self->_get_tables_used_in_columns(
            %args,
            tables  => $tables,
            columns => $query_struct->{columns},
         );
         foreach my $table ( @$clist_tables ) {
            my $table_usage = {
               context => 'SELECT',
               table   => $table,
            };
            MKDEBUG && _d("Table usage from CLIST:", Dumper($table_usage));
            push @{$tables_used[0]}, $table_usage;
         }
      }

      if ( @$tables > 1 || $query_type ne 'SELECT' ) {
         my $default_context = @$tables > 1 ? 'TLIST' : $query_type;
         foreach my $table ( @$tables ) {
            my $qualified_table = $self->_qualify_table_name(
               %args,
               tables => $tables,
               db     => $table->{db},
               tbl    => $table->{tbl},
            );

            my $context = $default_context;
            if ( $table->{join} && $table->{join}->{condition} ) {
                $context = 'JOIN';
               if ( $table->{join}->{condition} eq 'using' ) {
                  MKDEBUG && _d("Table joined with USING condition");
                  my $joined_table  = $self->_qualify_table_name(
                     %args,
                     tables => $tables,
                     tbl    => $table->{join}->{to},
                  );
                  $self->_change_context(
                     tables      => $tables,
                     table       => $joined_table,
                     tables_used => $tables_used[0],
                     old_context => 'TLIST',
                     new_context => 'JOIN',
                  );
               }
               elsif ( $table->{join}->{condition} eq 'on' ) {
                  MKDEBUG && _d("Table joined with ON condition");
                  my $on_tables = $self->_get_tables_used_in_where(
                     %args,
                     tables => $tables,
                     where  => $table->{join}->{where},
                     clause => 'JOIN condition',  # just for debugging
                  );
                  MKDEBUG && _d("JOIN ON tables:", Dumper($on_tables));
                  foreach my $joined_table ( @{$on_tables->{joined_tables}} ) {
                     $self->_change_context(
                        tables      => $tables,
                        table       => $joined_table,
                        tables_used => $tables_used[0],
                        old_context => 'TLIST',
                        new_context => 'JOIN',
                     );
                  }
               }
               else {
                  warn "Unknown JOIN condition: $table->{join}->{condition}";
               }
            }

            my $table_usage = {
               context => $context,
               table   => $qualified_table,
            };
            MKDEBUG && _d("Table usage from TLIST:", Dumper($table_usage));
            push @{$tables_used[0]}, $table_usage;
         }
      }

      if ( $where && $where->{joined_tables} ) {
         foreach my $joined_table ( @{$where->{joined_tables}} ) {
            MKDEBUG && _d("Table joined implicitly in WHERE:", $joined_table);
            $self->_change_context(
               tables      => $tables,
               table       => $joined_table,
               tables_used => $tables_used[0],
               old_context => 'TLIST',
               new_context => 'JOIN',
            );
         }
      }

      if ( $query_type =~ m/(?:INSERT|REPLACE)/ ) {
         if ( $query_struct->{select} ) {
            MKDEBUG && _d("Getting tables used in INSERT-SELECT");
            my $select_tables = $self->_get_tables_used_from_query_struct(
               %args,
               query_struct => $query_struct->{select},
            );
            push @{$tables_used[0]}, @{$select_tables->[0]};
         }
         else {
            my $table_usage = {
               context => 'SELECT',
               table   => $self->{constant_data_value},
            };
            MKDEBUG && _d("Table usage from SET/VALUES:", Dumper($table_usage));
            push @{$tables_used[0]}, $table_usage;
         }
      }
      elsif ( $query_type eq 'UPDATE' ) {
         my $set_tables = $self->_get_tables_used_in_set(
            %args,
            tables => $tables,
            set    => $query_struct->{set},
         );
         foreach my $table ( @$set_tables ) {
            my $table_usage = {
               context => 'SELECT',
               table   => $table->{value_is_table} ? $table->{table}
                        :                            $self->{constant_data_value},
            };
            MKDEBUG && _d("Table usage from SET:", Dumper($table_usage));
            push @{$tables_used[0]}, $table_usage;
         }
      }

      if ( $where && $where->{filter_tables} ) {
         foreach my $table ( @{$where->{filter_tables}} ) {
            my $table_usage = {
               context => 'WHERE',
               table   => $table,
            };
            MKDEBUG && _d("Table usage from WHERE:", Dumper($table_usage));
            push @{$tables_used[0]}, $table_usage;
         }
      }
   }

   return \@tables_used;
}

sub _get_tables_used_in_columns {
   my ( $self, %args ) = @_;
   my @required_args = qw(tables columns);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables, $columns) = @args{@required_args};

   MKDEBUG && _d("Getting tables used in CLIST");
   my @tables;

   if ( @$tables == 1 ) {
      # SELECT a, b FROM t WHERE ... -- one table so cols a and b must
      # be from that table.
      MKDEBUG && _d("Single table SELECT:", $tables->[0]->{tbl});
      my $table = $self->_qualify_table_name(
         %args,
         db  => $tables->[0]->{db},
         tbl => $tables->[0]->{tbl},
      );
      @tables = ($table);
   }
   elsif ( @$columns == 1 && $columns->[0]->{col} eq '*' ) {
      if ( $columns->[0]->{tbl} ) {
         # SELECT t1.* FROM ... -- selecting only from table t1
         MKDEBUG && _d("SELECT all columns from one table");
         my $table = $self->_qualify_table_name(
            %args,
            db  => $columns->[0]->{db},
            tbl => $columns->[0]->{tbl},
         );
         @tables = ($table);
      }
      else {
         # SELECT * FROM ... -- selecting from all tables
         MKDEBUG && _d("SELECT all columns from all tables");
         foreach my $table ( @$tables ) {
            my $table = $self->_qualify_table_name(
               %args,
               tables => $tables,
               db     => $table->{db},
               tbl    => $table->{tbl},
            );
            push @tables, $table;
         }
      }
   }
   else {
      # SELECT x, y FROM t1, t2 -- have to determine from which table each
      # column is.
      MKDEBUG && _d(scalar @$tables, "table SELECT");
      my %seen;
      COLUMN:
      foreach my $column ( @$columns ) {
         next COLUMN unless $column->{tbl};
         my $table = $self->_qualify_table_name(
            %args,
            db  => $column->{db},
            tbl => $column->{tbl},
         );
         push @tables, $table if $table && !$seen{$table}++;
      }
   }

   return \@tables;
}

sub _get_tables_used_in_where {
   my ( $self, %args ) = @_;
   my @required_args = qw(tables where);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables, $where) = @args{@required_args};
   my $sql_parser = $self->{SQLParser};

   MKDEBUG && _d("Getting tables used in", $args{clause} || 'WHERE');

   my %filter_tables;
   my %join_tables;
   CONDITION:
   foreach my $cond ( @$where ) {
      MKDEBUG && _d("Condition:", Dumper($cond));
      my @tables;  # tables used in this condition
      my $n_vals        = 0;
      my $is_constant   = 0;
      my $unknown_table = 0;
      ARG:
      foreach my $arg ( qw(left_arg right_arg) ) {
         if ( !defined $cond->{$arg} ) {
            MKDEBUG && _d($arg, "is a constant value");
            $is_constant = 1;
            next ARG;
         }

         if ( $sql_parser->is_identifier($cond->{$arg}) ) {
            MKDEBUG && _d($arg, "is an identifier");
            my $ident_struct = $sql_parser->parse_identifier(
               'column',
               $cond->{$arg}
            );

            if ( !$ident_struct->{tbl} ) {
               if ( @$tables == 1 ) {
                  MKDEBUG && _d("Condition column is not table-qualified; ",
                     "using query's only table:", $tables->[0]->{tbl});
                  $ident_struct->{tbl} = $tables->[0]->{tbl};
               }
               else {
                  MKDEBUG && _d("Condition column is not table-qualified and",
                     "query has multiple tables; cannot determine its table");
                  if (  $cond->{$arg} !~ m/\w+\(/       # not a function
                     && $cond->{$arg} !~ m/^[\d.]+$/) { # not a number
                     $unknown_table = 1;
                  }
                  next ARG;
               }
            }

            if ( !$ident_struct->{db} && @$tables == 1 && $tables->[0]->{db} ) {
               MKDEBUG && _d("Condition column is not database-qualified; ",
                  "using its table's database:", $tables->[0]->{db});
               $ident_struct->{db} = $tables->[0]->{db};
            }

            my $table = $self->_qualify_table_name(
               %args,
               %$ident_struct,
            );
            if ( $table ) {
               push @tables, $table;
            }
         }
         else {
            MKDEBUG && _d($arg, "is a value");
            $n_vals++;
         }
      }  # ARG

      if ( $is_constant || $n_vals == 2 ) {
         MKDEBUG && _d("Condition is a constant or two values");
         $filter_tables{$self->{constant_data_value}} = undef;
      }
      else {
         if ( @tables == 1 ) {
            if ( $unknown_table ) {
               MKDEBUG && _d("Condition joins table",
                  $tables[0], "to column from unknown table");
               $join_tables{$tables[0]} = undef;
            }
            else {
               MKDEBUG && _d("Condition filters table", $tables[0]);
               $filter_tables{$tables[0]} = undef;
            }
         }
         elsif ( @tables == 2 ) {
            MKDEBUG && _d("Condition joins tables",
               $tables[0], "and", $tables[1]);
            $join_tables{$tables[0]} = undef;
            $join_tables{$tables[1]} = undef;
         }
      }
   }  # CONDITION

   # NOTE: the sort is not necessary, it's done so test can be deterministic.
   return {
      filter_tables => [ sort keys %filter_tables ],
      joined_tables => [ sort keys %join_tables   ],
   };
}

sub _get_tables_used_in_set {
   my ( $self, %args ) = @_;
   my @required_args = qw(tables set);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables, $set) = @args{@required_args};
   my $sql_parser = $self->{SQLParser};

   MKDEBUG && _d("Getting tables used in SET");

   my @tables;
   if ( @$tables == 1 ) {
      my $table = $self->_qualify_table_name(
         %args,
         db  => $tables->[0]->{db},
         tbl => $tables->[0]->{tbl},
      );
      $tables[0] = {
         table => $table,
         value => $self->{constant_data_value}
      };
   }
   else {
      foreach my $cond ( @$set ) {
         next unless $cond->{tbl};
         my $table = $self->_qualify_table_name(
            %args,
            db  => $cond->{db},
            tbl => $cond->{tbl},
         );

         my $value          = $self->{constant_data_value};
         my $value_is_table = 0;
         if ( $sql_parser->is_identifier($cond->{value}) ) {
            my $ident_struct = $sql_parser->parse_identifier(
               'column',
               $cond->{value},
            );
            $value_is_table = 1;
            $value          = $self->_qualify_table_name(
               %args,
               db  => $ident_struct->{db},
               tbl => $ident_struct->{tbl},
            );
         }

         push @tables, {
            table          => $table,
            value          => $value,
            value_is_table => $value_is_table,
         };
      }
   }

   return \@tables;
}

sub _get_real_table_name {
   my ( $self, %args ) = @_;
   my @required_args = qw(tables name);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables, $name) = @args{@required_args};

   foreach my $table ( @$tables ) {
      if ( $table->{tbl} eq $name
           || ($table->{alias} || "") eq $name ) {
         MKDEBUG && _d("Real table name for", $name, "is", $table->{tbl});
         return $table->{tbl};
      }
   }
   # The named thing isn't referenced as a table by the query, so it's
   # probably a function or something else.
   MKDEBUG && _d("Table", $name, "does not exist in query");
   return;
}

sub _qualify_table_name {
   my ( $self, %args) = @_;
   my @required_args = qw(tables tbl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables, $table) = @args{@required_args};

   MKDEBUG && _d("Qualifying table with database:", $table);

   my ($tbl, $db) = reverse split /[.]/, $table;

   # Always use real table names, not alias.
   $tbl = $self->_get_real_table_name(%args, name => $tbl);
   return unless $tbl;  # shouldn't happen

   my $db_tbl;

   if ( $db ) {
      # Table was already db-qualified.
      $db_tbl = "$db.$tbl";
   }
   elsif ( $args{db} ) {
      # Database given, use it.
      $db_tbl = "$args{db}.$tbl";
   }
   else {
      # If no db is given, see if the table is db-qualified.
      foreach my $tbl_info ( @$tables ) {
         if ( ($tbl_info->{tbl} eq $tbl) && $tbl_info->{db} ) {
            $db_tbl = "$tbl_info->{db}.$tbl";
            last;
         }
      }

      # Last resort: use default db if it's given.
      if ( !$db_tbl && $args{default_db} ) { 
         $db_tbl = "$args{default_db}.$tbl";
      }

      # Can't db-qualify the table, so return just the real table name.
      if ( !$db_tbl ) {
         MKDEBUG && _d("Cannot determine database for table", $tbl);
         $db_tbl = $tbl;
      }
   }

   MKDEBUG && _d("Table qualified with database:", $db_tbl);
   return $db_tbl;
}

sub _change_context {
   my ( $self, %args) = @_;
   my @required_args = qw(tables_used table old_context new_context tables);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables_used, $table, $old_context, $new_context) = @args{@required_args};
   MKDEBUG && _d("Change context of table", $table, "from", $old_context,
      "to", $new_context);
   foreach my $used_table ( @$tables_used ) {
      if (    $used_table->{table}   eq $table
           && $used_table->{context} eq $old_context ) {
         $used_table->{context} = $new_context;
         return;
      }
   }
   MKDEBUG && _d("Table", $table, "is not used; cannot set its context");
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
# End TableUsage package
# ###########################################################################
