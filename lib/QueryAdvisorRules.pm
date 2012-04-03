# This program is copyright 2010-2011 Percona Inc.
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
# QueryAdvisorRules package
# ###########################################################################
{
# Package: QueryAdvisorRules
# QueryAdvisorRules encapsulates rules for checking queries.
package QueryAdvisorRules;
use base 'AdvisorRules';

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = $class->SUPER::new(%args);
   @{$self->{rules}} = $self->get_rules();
   PTDEBUG && _d(scalar @{$self->{rules}}, "rules");
   return $self;
}

# Each rules is a hashref with two keys:
#   * id       Unique PREFIX.NUMBER for the rule.  The prefix is three chars
#              which hints to the nature of the rule.  See example below.
#   * code     Coderef to check rule, returns undef if rule does not match,
#              else returns the string pos near where the rule matches or 0
#              to indicate it doesn't know the pos.  The code is passed a\
#              single arg: a hashref event.
sub get_rules {
   return
   {
      id   => 'ALI.001',      # Implicit alias
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         foreach my $tbl ( @$tbls ) {
            return 0 if $tbl->{alias} && !$tbl->{explicit_alias};
         }
         my $cols = $struct->{columns};
         return unless $cols;
         foreach my $col ( @$cols ) {
            return 0 if $col->{alias} && !$col->{explicit_alias};
         }
         return;
      },
   },
   {
      id   => 'ALI.002',      # tbl.* alias
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         my $cols  = $event->{query_struct}->{columns};
         return unless $cols;
         foreach my $col ( @$cols ) {
            return 0 if $col->{tbl} && $col->{col} eq '*' &&  $col->{alias};
         }
         return;
      },
   },
   {
      id   => 'ALI.003',      # tbl AS tbl
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         foreach my $tbl ( @$tbls ) {
            return 0 if $tbl->{alias} && $tbl->{alias} eq $tbl->{tbl};
         }
         my $cols = $struct->{columns};
         return unless $cols;
         foreach my $col ( @$cols ) {
            return 0 if $col->{alias} && $col->{alias} eq $col->{col};
         }
         return;
      },
   },
   {
      id   => 'ARG.001',      # col = '%foo'
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         my $where = $event->{query_struct}->{where};
         return unless $where && @$where;
         foreach my $arg ( @$where ) {
            return 0
               if ($arg->{operator} || '') eq 'like'
                  && $arg->{right_arg} =~ m/[\'\"][\%\_]./;
         }
         return;
      },
   },
   {
      id   => 'ARG.002',      # LIKE w/o wildcard
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};        
         my $where = $event->{query_struct}->{where};
         return unless $where && @$where;
         foreach my $arg ( @$where ) {
            return 0
               if ($arg->{operator} || '') eq 'like'
                  && $arg->{right_arg} !~ m/[%_]/;
         }
         return;
      },
   },
   {
      id   => 'CLA.001',      # SELECT w/o WHERE
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return unless ($event->{query_struct}->{type} || '') eq 'select';
         return unless $event->{query_struct}->{from};
         return 0 unless $event->{query_struct}->{where};
         return;
      },
   },
   {
      id   => 'CLA.002',      # ORDER BY RAND()
      code => sub {
         my ( %args ) = @_;
         my $event   = $args{event};
         my $orderby = $event->{query_struct}->{order_by};
         return unless $orderby;
         foreach my $ident ( @$orderby ) {
            # SQLParser will have uppercased the function name.
            return 0 if $ident->{function} && $ident->{function} eq 'RAND';
         }
         return;
      },
   },
   {
      id   => 'CLA.003',      # LIMIT w/ OFFSET
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return unless $event->{query_struct}->{limit};
         return unless defined $event->{query_struct}->{limit}->{offset};
         return 0;
      },
   },
   {
      id   => 'CLA.004',      # GROUP BY <number>
      code => sub {
         my ( %args ) = @_;
         my $event   = $args{event};
         my $groupby = $event->{query_struct}->{group_by};
         return unless $groupby;
         foreach my $ident ( @$groupby ) {
            return 0 if exists $ident->{position};
         }
         return;
      },
   },
   {
      id   => 'CLA.005',      # ORDER BY col where col=<constant>
      code => sub {
         my ( %args ) = @_;
         my $event   = $args{event};
         my $orderby = $event->{query_struct}->{order_by};
         return unless $orderby;
         my $where   = $event->{query_struct}->{where};
         return unless $where;
         my %orderby_col = map { lc $_->{column} => 1 }
                           grep { $_->{column} }
                           @$orderby;
         foreach my $pred ( @$where ) {
            my $val = $pred->{right_arg};
            next unless $val;
            return 0 if $val =~ m/^\d+$/ && $orderby_col{lc($pred->{left_arg} || '')};
         }
         return;
      },
   },
   {
      id   => 'CLA.006',      # GROUP BY or ORDER BY different tables
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         my $groupby = $event->{query_struct}->{group_by};
         my $orderby = $event->{query_struct}->{order_by};
         return unless $groupby || $orderby;

         my %groupby_tbls = map { $_->{table} => 1 }
                            grep { $_->{table} }
                            @$groupby;
         return 0 if scalar keys %groupby_tbls > 1;
         
         my %orderby_tbls = map { $_->{table} => 1 }
                            grep { $_->{table} }
                            @$orderby;
         return 0 if scalar keys %orderby_tbls > 1;

         # Remove ORDER BY tables from GROUP BY tables.  Any tables
         # remain in GROUP BY are unique to GROUP BY, i.e. not in
         # ORDER BY, so we have a case like: group by tbl1.id order by tbl2.id
         map { delete $groupby_tbls{$_} } keys %orderby_tbls;
         return 0 if scalar keys %groupby_tbls;

         return;
      },
   },
   {
      id   => 'CLA.007',      # ORDER BY ASC/DESC mix can't use index
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         my $order_by = $event->{query_struct}->{order_by}; 
         return unless $order_by;
         my ($asc, $desc) = (0, 0);
         foreach my $col ( @$order_by ) {
            if ( ($col->{sort} || 'ASC') eq 'ASC' ) {
               $asc++;
            }
            else {
               $desc++;
            }
            return 0 if $asc && $desc;
         }
         return;
      },
   },
   {
      id   => 'COL.001',      # SELECT *
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return unless ($event->{query_struct}->{type} || '') eq 'select';
         my $cols = $event->{query_struct}->{columns};
         return unless $cols;
         foreach my $col ( @$cols ) {
            return 0 if $col->{col} eq '*';
         }
         return;
      },
   },
   {
      id   => 'COL.002',      # INSERT w/o (cols) def
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         my $type  = $event->{query_struct}->{type} || '';
         return unless $type eq 'insert' || $type eq 'replace';
         return 0 unless $event->{query_struct}->{columns};
         return;
      },
   },
   {
      id   => 'LIT.001',      # IP as string
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         if ( $event->{arg} =~ m/['"]\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/gc ) {
            return (pos $event->{arg}) || 0;
         }
         return;
      },
   },
   {
      id   => 'LIT.002',      # Date not quoted
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         # YYYY-MM-DD
         if ( $event->{arg} =~ m/(?<!['"\w-])\d{4}-\d{1,2}-\d{1,2}\b/gc ) {
            return (pos $event->{arg}) || 0;
         }
         # YY-MM-DD
         if ( $event->{arg} =~ m/(?<!['"\w\d-])\d{2}-\d{1,2}-\d{1,2}\b/gc ) {
            return (pos $event->{arg}) || 0;
         }
         return;
      },
   },
   {
      id   => 'KWR.001',      # SQL_CALC_FOUND_ROWS
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return 0 if $event->{query_struct}->{keywords}->{sql_calc_found_rows};
         return;
      },
   },
   {
      id   => 'JOI.001',      # comma and ansi joins
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         my $comma_join = 0;
         my $ansi_join  = 0;
         foreach my $tbl ( @$tbls ) {
            if ( $tbl->{join} ) {
               if ( $tbl->{join}->{ansi} ) {
                  $ansi_join = 1;
               }
               else {
                  $comma_join = 1;
               }
            }
            return 0 if $comma_join && $ansi_join;
         }
         return;
      },
   },
   {
      id   => 'RES.001',      # non-deterministic GROUP BY
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return unless ($event->{query_struct}->{type} || '') eq 'select';
         my $groupby = $event->{query_struct}->{group_by};
         return unless $groupby;
         # Only check GROUP BY column names, not numbers.  GROUP BY number
         # is handled in CLA.004.
         my %groupby_col = map { $_->{column} => 1 }
                           grep { $_->{column} }
                           @$groupby;
         return unless scalar %groupby_col;
         my $cols = $event->{query_struct}->{columns};
         # All SELECT cols must be in GROUP BY cols clause.
         # E.g. select a, b, c from tbl group by a; -- non-deterministic
         foreach my $col ( @$cols ) {
            return 0 unless $groupby_col{ $col->{col} };
         }
         return;
      },
   },
   {
      id   => 'RES.002',      # non-deterministic LIMIT w/o ORDER BY
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return unless $event->{query_struct}->{limit};
         # If query doesn't use tables then this check isn't applicable.
         return unless    $event->{query_struct}->{from}
                         || $event->{query_struct}->{into}
                         || $event->{query_struct}->{tables};
         return 0 unless $event->{query_struct}->{order_by};
         return;
      },
   },
   {
      id   => 'STA.001',      # != instead of <>
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return 0 if $event->{arg} =~ m/!=/;
         return;
      },
   },
   {
      id   => 'SUB.001',      # IN(<subquery>)
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         if ( $event->{arg} =~ m/\bIN\s*\(\s*SELECT\b/gi ) {
            return pos $event->{arg};
         }
         return;
      },
   },
   {
      id   => 'JOI.002',      # table joined more than once, but not self-join
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         return unless $struct;
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         my %tbl_cnt;
         my $n_tbls = scalar @$tbls;

         # To detect this rule we look for tables joined more than once
         # (if cnt > 1) and via both an ansi and comma join.  This captures
         # "t AS a JOIN t AS b a.foo=b.bar, t" but not the simple self-join
         # "t AS a JOIN t AS b a.foo=b.bar" or cases where a table is joined
         # to many other tables all via ansi joins or the implicit self-join
         # (which we really can't detect) "t AS a, t AS b WHERE a.foo=b.bar".
         # When a table shows up multiple times in ansi joins and then again
         # in a comma join, the comma join is usually culprit of this rule.
         for my $i ( 0..($n_tbls-1) ) {
            my $tbl      = $tbls->[$i];
            my $tbl_name = lc $tbl->{tbl};

            $tbl_cnt{$tbl_name}->{cnt}++;
            $tbl_cnt{$tbl_name}->{ansi_join}++
               if $tbl->{join} && $tbl->{join}->{ansi};
            $tbl_cnt{$tbl_name}->{comma_join}++
               if $tbl->{join} && !$tbl->{join}->{ansi};

            if ( $tbl_cnt{$tbl_name}->{cnt} > 1 ) {
               return 0
                  if    $tbl_cnt{$tbl_name}->{ansi_join}
                     && $tbl_cnt{$tbl_name}->{comma_join};
            }
         }
         return;
      },
   },
   {
      id   => 'JOI.003',  # OUTER JOIN converted to INNER JOIN
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         return unless $struct;
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         my $where  = $struct->{where};
         return unless $where;

         # Good LEFT OUTER JOIN:
         #   select * from L left join R using(c) where L.a=5;
         # Converts to INNER JOIN when:
         #   select * from L left join R using(c) where L.a=5 and R.b=10;
         # To detect this condition we need to see if there's an OUTER
         # join then see if there's a column from the outer table in the
         # WHERE clause that is anything but "IS NULL".  So in the example
         # above, R.b=10 is this culprit.
         # http://code.google.com/p/maatkit/issues/detail?id=950
         my %outer_tbls = map { $_->{tbl} => 1 } get_outer_tables($tbls);
         PTDEBUG && _d("Outer tables:", keys %outer_tbls);
         return unless %outer_tbls;

         foreach my $pred ( @$where ) {
            next unless $pred->{left_arg};  # skip constants like 1 in "WHERE 1"
            my ($tbl, $col) = split /\./, $pred->{left_arg};
            if ( $tbl && $col && $outer_tbls{$tbl} ) {
               # Only outer_tbl.col IS NULL is permissible.
               if ($pred->{operator} ne 'is' || $pred->{right_arg} !~ m/null/i)
               {
                  PTDEBUG && _d("Predicate prevents OUTER JOIN:",
                     map { $pred->{$_} } qw(left_arg operator right_arg));
                  return 0;
               }
            }
         }

         return;
      }
   },
   {
      id   => 'JOI.004',  # broken exclusion join
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         return unless $struct;
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         my $where  = $struct->{where};
         return unless $where;

         my %outer_tbls;
         my %outer_tbl_join_cols;
         my @unknown_join_cols;
         foreach my $outer_tbl ( get_outer_tables($tbls) ) {
            $outer_tbls{$outer_tbl->{tbl}} = 1;

            # For "L LEFT JOIN R" R is the outer table and since it follows
            # L its table struct will have the join struct with the join
            # condition.  But for "L RIGHT JOIN R" L is the outer table and
            # will not have the join struct because it precedes R.  This
            # is due to how parse_from() works.  So if the outer table doesn't
            # have the join struct, we need to get it from the inner table.
            my $join = $outer_tbl->{join};
            if ( !$join ) {
               my ($inner_tbl) = grep { 
                  exists $_->{join} 
                  && $_->{join}->{to} eq $outer_tbl->{tbl}
               } @$tbls;
               $join = $inner_tbl->{join}; 
               die "Cannot find join structure for $outer_tbl->{tbl}"
                  unless $join;
            }

            # Get the outer table columns used in the jon condition.
            if ( $join->{condition} eq 'using' ) {
               %outer_tbl_join_cols = map { $_ => 1 } @{$join->{columns}};
            }
            else {
               my $where = $join->{where};
               die "Join structure for ON condition has no where structure"
                  unless $where;
               my @join_cols;
               foreach my $pred ( @$where ) {
                  next unless $pred->{operator} eq '=';
                  # Assume all equality comparisons are like tbl1.col=tbl2.col.
                  # Thus join conditions like tbl1.col<tbl2.col aren't handled.
                  push @join_cols, $pred->{left_arg}, $pred->{right_arg};
               }
               PTDEBUG && _d("Join columns:", @join_cols);
               foreach my $join_col ( @join_cols ) {
                  my ($tbl, $col) = split /\./, $join_col;
                  if ( !$col ) {
                     $col = $tbl;
                     $tbl = determine_table_for_column(
                        column      => $col,
                        tbl_structs => $event->{tbl_structs},
                     );
                  }
                  if ( !$tbl ) {
                     PTDEBUG && _d("Cannot determine the table for join column",
                        $col);
                     push @unknown_join_cols, $col;
                  }
                  else {
                     $outer_tbl_join_cols{$col} = 1
                        if $tbl eq $outer_tbl->{tbl};
                  }
               }
            }
         }
         PTDEBUG && _d("Outer table join columns:", keys %outer_tbl_join_cols);
         PTDEBUG && _d("Unknown join columns:", @unknown_join_cols);

         # Here's a problem query:
         #   select c from L left join R on L.a=R.b where L.a=5 and R.c is null
         # The problem is "R.c is null" will not allow one to determine if
         # a null row from the outer table is null due to not matching the
         # inner table or due to R.c actually having a null value.  So we
         # need to check every outer table column in the WHERE clause for
         # ones that are 1) not in the JOIN expression and 2) "IS NULL'.
         # http://code.google.com/p/maatkit/issues/detail?id=950
         foreach my $pred ( @$where ) {
            next unless $pred->{left_arg}; # skip constants like 1 in "WHERE 1"
            next unless $pred->{operator} eq 'is'
               && $pred->{right_arg} =~ m/NULL/i;

            my ($tbl, $col) = split /\./, $pred->{left_arg};
            if ( !$col ) {
               # A col in the WHERE clause isn't table-qualified.  Try to
               # determine its table.  If we can, great, if not "return 0 if"
               # below will immediately fail because $tbl will be undef still.
               # That's ok; it just means this test tries as best it can and
               # gets skipped silently when we can't tbl-qualify cols.
               $col = $tbl;
               $tbl = determine_table_for_column(
                  column      => $col,
                  tbl_structs => $event->{tbl_structs},
               );
            }
            next unless $tbl;               # can't check tbl if tbl is unknown
            next unless $outer_tbls{$tbl};  # only want outer tbl cols

            # At this point we know col is from outer table and "IS NULL".
            # "outer_tbl.join_col IS NULL" is ok, but...
            next if $outer_tbl_join_cols{$col};

            # ...this rule could match here for two reasons.  First, if
            # we know the outer tbl join cols and this col isn't one of them
            # (hence the statement above passed and we got here), then
            # @unknown_join_cols will be empty and we'll match.  This is like
            # "outer_tbl.NON_join_col IS NULL".  Or second, we don't know
            # the outer tbl join cols and @unknown_join_cols will have cols
            # and we'll match if this col isn't one of the unknown join cols.
            # This is for cases like:
            #   select c from L left join R on a=b where L.a=5 and R.c is null
            # We don't know if a or b belong to L or R but we know c is from
            # the outer table and is neither a nor b.
            return 0 unless grep { $col eq $_ } @unknown_join_cols;
         }

         return;  # rule does not match, as best as we can determine
      }
   },
};


# Sub: get_outer_tables
#   Get the outer tables in joins.
#
# Parameters:
#   $tbls - Arrayref of hashrefs with table info
#
# Returns:
#   Array of hashref to the outer tables
sub get_outer_tables {
   my ( $tbls ) = @_;
   return unless $tbls;
   my @outer_tbls;
   my $n_tbls = scalar @$tbls;
   for my $i( 0..($n_tbls-1) ) {
      my $tbl = $tbls->[$i];
      next unless $tbl->{join} && $tbl->{join}->{type} =~ m/left|right/i;
      push @outer_tbls,
         $tbl->{join}->{type} =~ m/left/i ? $tbl
                                          : $tbls->[$i - 1];
   }
   return @outer_tbls;
}


# Sub: determine_table_for_column
#   Determine which table a column belongs to.  No extensive, online effort
#   is made to determine the column's table.  The caller is responsible for
#   using the parsed SQL structure to get its db/tables and their tbl structs
#   and providing a list of them.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   column - column name, not quoted
#
# Optional Arguments:
#   tbl_structs - arrayref hashrefs returned by <TableParser::parse()>
#
# Returns:
#   Table name, not quoted
sub determine_table_for_column {
   my ( %args ) = @_;
   my @required_args = qw(column);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($col) = @args{@required_args};

   my $tbl_structs = $args{tbl_structs};
   return unless $tbl_structs;

   foreach my $db ( keys %$tbl_structs ) {
      foreach my $tbl ( keys %{$tbl_structs->{$db}} ) {
         if ( $tbl_structs->{$db}->{$tbl}->{is_col}->{$col} ) {
            PTDEBUG && _d($col, "column belongs to", $db, $tbl);
            return $tbl;
         }
      }
   }

   PTDEBUG && _d("Cannot determine table for column", $col);
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
# End QueryAdvisorRules package
# ###########################################################################
