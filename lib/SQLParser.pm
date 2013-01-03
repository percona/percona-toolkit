# This program is copyright 2010-2012 Percona Ireland Ltd.
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
# SQLParser package
# ###########################################################################
{
# Package: SQLParser
# SQLParser parses common MySQL SQL statements into data structures.
# This parser is MySQL-specific and intentionally meant to handle only
# "common" cases.  Although there are many limiations (like UNION, CASE,
# etc.), many complex cases are handled that no other free, Perl SQL
# parser at the time of writing can parse, notably subqueries in all their
# places and varieties.
#
# This package has not been profiled and since it relies heavily on
# mildly complex regex, so do not expect amazing performance.
#
# See SQLParser.t for examples of the various data structures.  There are
# many and they vary a lot depending on the statment parsed, so documentation
# in this file is not exhaustive.
#
# This package differs from QueryParser because here we parse the entire SQL
# statement (thus giving access to all its parts), whereas QueryParser extracts
# just needed parts (and ignores all the rest).
package SQLParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Basic identifers for database, table, column and function names.
my $quoted_ident   = qr/`[^`]+`/;
my $unquoted_ident = qr/
   \@{0,2}         # optional @ or @@ for variables
   \w+             # the ident name
   (?:\([^\)]*\))? # optional function params
/x;

my $ident_alias = qr/
  \s+                                 # space before alias
  (?:(AS)\s+)?                        # optional AS keyword
  ((?>$quoted_ident|$unquoted_ident)) # alais
/xi;

# A table is identified by 1 or 2 identifiers separated by a period
# and optionally followed by an alias.  See parse_table_reference()
# for why an optional index hint is not included here.
my $table_ident = qr/(?:
   ((?:(?>$quoted_ident|$unquoted_ident)\.?){1,2}) # table
   (?:$ident_alias)?                               # optional alias
)/xo;

# A column is identified by 1 to 3 identifiers separated by periods
# and optionally followed by an alias.
my $column_ident = qr/(?:
   ((?:(?>$quoted_ident|$unquoted_ident|\*)\.?){1,3}) # column
   (?:$ident_alias)?                                  # optional alias
)/xo;

my $function_ident = qr/
   \b
   (
      \w+      # function name
      \(       # opening parenthesis
      [^\)]+   # function args, if any
      \)       # closing parenthesis
   )
/x;

my %ignore_function = (
   INDEX => 1,
   KEY   => 1,
);

# Sub: new
#   Create a SQLParser object.
#
# Parameters:
#   %args - Arguments
#
# Optional Arguments:
#   Schema - <Schema> object.  Can be set later by calling <set_Schema()>.
#
# Returns:
#   SQLParser object
sub new {
   my ( $class, %args ) = @_;
   my $self = {
      %args,
   };
   return bless $self, $class;
}

# Sub: parse
#   Parse a SQL statment.   Only statements of $allowed_types are parsed.
#   This sub recurses to parse subqueries.
#
# Parameters:
#   $query - SQL statement
#
# Returns:
#   A complex hashref of the parsed SQL statment.  All keys and almost all
#   values are lowercase for consistency.  The struct is roughly:
#   (start code)
#   {
#     type       => '',     # one of $allowed_types
#     clauses    => {},     # raw, unparsed text of clauses
#     <clause>   => struct  # parsed clause struct, e.g. from => [<tables>]
#     keywords   => {},     # LOW_PRIORITY, DISTINCT, SQL_CACHE, etc.
#     functions  => {},     # MAX(), SUM(), NOW(), etc.
#     select     => {},     # SELECT struct for INSERT/REPLACE ... SELECT
#     subqueries => [],     # pointers to subquery structs
#   }
#   (end code)
#   It varies, of course, depending on the query.  If something is missing
#   it means the query doesn't have that part.  E.g. INSERT has an INTO clause
#   but DELETE does not, and only DELETE and SELECT have FROM clauses.  Each
#   clause struct is different; see their respective parse_CLAUSE subs.
sub parse {
   my ( $self, $query ) = @_;
   return unless $query;

   # Only these types of statements are parsed.
   my $allowed_types = qr/(?:
       DELETE
      |INSERT
      |REPLACE
      |SELECT
      |UPDATE
      |CREATE
   )/xi;

   # Flatten and clean query.
   $query = $self->clean_query($query);

   # Remove first word, should be the statement type.  The parse_TYPE subs
   # expect that this is already removed.
   my $type;
   if ( $query =~ s/^(\w+)\s+// ) {
      $type = lc $1;
      PTDEBUG && _d('Query type:', $type);
      die "Cannot parse " . uc($type) . " queries"
         unless $type =~ m/$allowed_types/i;
   }
   else {
      die "Query does not begin with a word";  # shouldn't happen
   }

   $query = $self->normalize_keyword_spaces($query);

   # If query has any subqueries, remove/save them and replace them.
   # They'll be parsed later, after the main outer query.
   my @subqueries;
   if ( $query =~ m/(\(SELECT )/i ) {
      PTDEBUG && _d('Removing subqueries');
      @subqueries = $self->remove_subqueries($query);
      $query      = shift @subqueries;
   }
   elsif ( $type eq 'create' && $query =~ m/\s+SELECT/ ) {
      PTDEBUG && _d('CREATE..SELECT');
      ($subqueries[0]->{query}) = $query =~ m/\s+(SELECT .+)/;
      $query =~ s/\s+SELECT.+//;
   }

   # Parse raw text parts from query.  The parse_TYPE subs only do half
   # the work: parsing raw text parts of clauses, tables, functions, etc.
   # Since these parts are invariant (e.g. a LIMIT clause is same for any
   # type of SQL statement) they are parsed later via other parse_CLAUSE
   # subs, instead of parsing them individually in each parse_TYPE sub.
   my $parse_func = "parse_$type";
   my $struct     = $self->$parse_func($query);
   if ( !$struct ) {
      PTDEBUG && _d($parse_func, 'failed to parse query');
      return;
   }
   $struct->{type} = $type;
   $self->_parse_clauses($struct);
   # TODO: parse functions

   if ( @subqueries ) {
      PTDEBUG && _d('Parsing subqueries');
      foreach my $subquery ( @subqueries ) {
         my $subquery_struct = $self->parse($subquery->{query});
         @{$subquery_struct}{keys %$subquery} = values %$subquery;
         push @{$struct->{subqueries}}, $subquery_struct;
      }
   }

   PTDEBUG && _d('Query struct:', Dumper($struct));
   return $struct;
}


# Sub: _parse_clauses
#   Parse raw text of clauses into data structures.  This sub recurses
#   to parse the clauses of subqueries.  The clauses are read from
#   and their data structures saved into the $struct parameter.
#
# Parameters:
#   $struct - Hashref from which clauses are read (%{$struct->{clauses}})
#             and into which data structs are saved (e.g. $struct->{from}=...).
sub _parse_clauses {
   my ( $self, $struct ) = @_;
   # Parse raw text of clauses and functions.
   foreach my $clause ( keys %{$struct->{clauses}} ) {
      # Rename/remove clauses with space in their names, like ORDER BY.
      if ( $clause =~ m/ / ) {
         (my $clause_no_space = $clause) =~ s/ /_/g;
         $struct->{clauses}->{$clause_no_space} = $struct->{clauses}->{$clause};
         delete $struct->{clauses}->{$clause};
         $clause = $clause_no_space;
      }

      my $parse_func     = "parse_$clause";
      $struct->{$clause} = $self->$parse_func($struct->{clauses}->{$clause});

      if ( $clause eq 'select' ) {
         PTDEBUG && _d('Parsing subquery clauses');
         $struct->{select}->{type} = 'select';
         $self->_parse_clauses($struct->{select});
      }
   }
   return;
}

# Sub: clean_query
#   Remove spaces, flatten, and normalize some patterns for easier parsing.
#
# Parameters:
#   $query - SQL statement
#
# Returns:
#   Cleaned $query
sub clean_query {
   my ( $self, $query ) = @_;
   return unless $query;

   # Whitespace and comments.
   $query =~ s/^\s*--.*$//gm;  # -- comments
   $query =~ s/\s+/ /g;        # extra spaces/flatten
   $query =~ s!/\*.*?\*/!!g;   # /* comments */
   $query =~ s/^\s+//;         # leading spaces
   $query =~ s/\s+$//;         # trailing spaces

   return $query;
}

# Sub: normalize_keyword_spaces
#   Normalize spaces around certain SQL keywords.  Spaces are added and
#   removed around certain SQL keywords to make parsing easier.
#
# Parameters:
#   $query - SQL statement
#
# Returns:
#   Normalized $query
sub normalize_keyword_spaces {
   my ( $self, $query ) = @_;

   # Add spaces between important tokens to help the parse_* subs.
   $query =~ s/\b(VALUE(?:S)?)\(/$1 (/i;
   $query =~ s/\bON\(/on (/gi;
   $query =~ s/\bUSING\(/using (/gi;

   # Start of (SELECT subquery).
   $query =~ s/\(\s+SELECT\s+/(SELECT /gi;

   return $query;
}

# Sub: _parse_query
#    This sub is called by the parse_TYPE subs except parse_insert.
#    It does two things: remove, save the given keywords, all of which
#    should appear at the beginning of the query; and, save (but not
#    remove) the given clauses.  The query should start with the values
#    for the first clause because the query's first word was removed
#    in parse().  So for "SELECT cols FROM ...", the query given here
#    is "cols FROM ..." where "cols" belongs to the first clause "columns".
#    Then the query is walked clause-by-clause, saving each.
#
# Parameters:
#   $query        - SQL statement with first word (SELECT, INSERT, etc.) removed
#   $keywords     - Compiled regex of keywords that can appear in $query
#   $first_clause - First clause word to expect in $query
#   $clauses      - Compiled regex of clause words that can appear in $query
#
# Returns:
#   Hashref with raw text of clauses
sub _parse_query {
   my ( $self, $query, $keywords, $first_clause, $clauses ) = @_;
   return unless $query;
   my $struct = {};

   # Save, remove keywords.
   1 while $query =~ s/$keywords\s+/$struct->{keywords}->{lc $1}=1, ''/gie;

   # Go clausing.
   my @clause = grep { defined $_ }
      ($query =~ m/\G(.+?)(?:$clauses\s+|\Z)/gci);

   my $clause = $first_clause,
   my $value  = shift @clause;
   $struct->{clauses}->{$clause} = $value;
   PTDEBUG && _d('Clause:', $clause, $value);

   # All other clauses.
   while ( @clause ) {
      $clause = shift @clause;
      $value  = shift @clause;
      $struct->{clauses}->{lc $clause} = $value;
      PTDEBUG && _d('Clause:', $clause, $value);
   }

   ($struct->{unknown}) = ($query =~ m/\G(.+)/);

   return $struct;
}

sub parse_delete {
   my ( $self, $query ) = @_;
   if ( $query =~ s/FROM\s+//i ) {
      my $keywords = qr/(LOW_PRIORITY|QUICK|IGNORE)/i;
      my $clauses  = qr/(FROM|WHERE|ORDER BY|LIMIT)/i;
      return $self->_parse_query($query, $keywords, 'from', $clauses);
   }
   else {
      die "DELETE without FROM: $query";
   }
}

sub parse_insert {
   my ( $self, $query ) = @_;
   return unless $query;
   my $struct = {};

   # Save, remove keywords.
   my $keywords   = qr/(LOW_PRIORITY|DELAYED|HIGH_PRIORITY|IGNORE)/i;
   1 while $query =~ s/$keywords\s+/$struct->{keywords}->{lc $1}=1, ''/gie;

   if ( $query =~ m/ON DUPLICATE KEY UPDATE (.+)/i ) {
      my $values = $1;
      die "No values after ON DUPLICATE KEY UPDATE: $query" unless $values;
      $struct->{clauses}->{on_duplicate} = $values;
      PTDEBUG && _d('Clause: on duplicate key update', $values);

      # This clause can be confused for JOIN ... ON in INSERT-SELECT queries,
      # so we remove the ON DUPLICATE KEY UPDATE clause after extracting its
      # values.
      $query =~ s/\s+ON DUPLICATE KEY UPDATE.+//;
   }

   # Parse INTO clause.  Literal "INTO" is optional.
   if ( my @into = ($query =~ m/
            (?=.*?(?:VALUE|SE(?:T|LECT)))  # Avoid a backtracking explosion
            (?:INTO\s+)?            # INTO, optional
            (.+?)\s+                # table ref
            (\([^\)]+\)\s+)?        # column list, optional
            (VALUE.?|SET|SELECT)\s+ # start of next caluse
         /xgci)
   ) {
      my $tbl  = shift @into;  # table ref
      $struct->{clauses}->{into} = $tbl;
      PTDEBUG && _d('Clause: into', $tbl);

      my $cols = shift @into;  # columns, maybe
      if ( $cols ) {
         $cols =~ s/[\(\)]//g;
         $struct->{clauses}->{columns} = $cols;
         PTDEBUG && _d('Clause: columns', $cols);
      }

      my $next_clause = lc(shift @into);  # VALUES, SET or SELECT
      die "INSERT/REPLACE without clause after table: $query"
         unless $next_clause;
      $next_clause = 'values' if $next_clause eq 'value';
      my ($values) = ($query =~ m/\G(.+)/gci);
      die "INSERT/REPLACE without values: $query" unless $values;
      $struct->{clauses}->{$next_clause} = $values;
      PTDEBUG && _d('Clause:', $next_clause, $values);
   }

   # Save any leftovers.  If there are any, parsing missed something.
   ($struct->{unknown}) = ($query =~ m/\G(.+)/);

   return $struct;
}
{
   # Suppress warnings like "Name "SQLParser::parse_set" used only once:
   # possible typo at SQLParser.pm line 480." caused by the fact that we
   # don't call these aliases directly, they're called indirectly using
   # $parse_func, hence Perl can't see their being called a compile time.
   no warnings;
   # INSERT and REPLACE are so similar that they are both parsed
   # in parse_insert().
   *parse_replace = \&parse_insert;
}

sub parse_select {
   my ( $self, $query ) = @_;

   # Keywords are expected to be at the start of the query, so these
   # that appear at the end are handled separately.  Afaik, SELECT is
   # only statement with optional keywords at the end.  Also, these
   # appear to be the only keywords with spaces instead of _.
   my @keywords;
   my $final_keywords = qr/(FOR UPDATE|LOCK IN SHARE MODE)/i; 
   1 while $query =~ s/\s+$final_keywords/(push @keywords, $1), ''/gie;

   my $keywords = qr/(
       ALL
      |DISTINCT
      |DISTINCTROW
      |HIGH_PRIORITY
      |STRAIGHT_JOIN
      |SQL_SMALL_RESULT
      |SQL_BIG_RESULT
      |SQL_BUFFER_RESULT
      |SQL_CACHE
      |SQL_NO_CACHE
      |SQL_CALC_FOUND_ROWS
   )/xi;
   my $clauses = qr/(
       FROM
      |WHERE
      |GROUP\sBY
      |HAVING
      |ORDER\sBY
      |LIMIT
      |PROCEDURE
      |INTO OUTFILE
   )/xi;
   my $struct = $self->_parse_query($query, $keywords, 'columns', $clauses);

   # Add final keywords, if any.
   map { s/ /_/g; $struct->{keywords}->{lc $_} = 1; } @keywords;

   return $struct;
}

sub parse_update {
   my $keywords = qr/(LOW_PRIORITY|IGNORE)/i;
   my $clauses  = qr/(SET|WHERE|ORDER BY|LIMIT)/i;
   return _parse_query(@_, $keywords, 'tables', $clauses);

}

sub parse_create {
   my ($self, $query) = @_;
   my ($obj, $name) = $query =~ m/
      (\S+)\s+
      (?:IF NOT EXISTS\s+)?
      (\S+)
   /xi;
   return {
      object  => lc $obj,
      name    => $name,
      unknown => undef,
   };
}

# Sub: parse_from
#   Parse a FROM clause, a.k.a. the table references.  Does not handle
#   nested joins.  See http://dev.mysql.com/doc/refman/5.1/en/join.html
#
# Parameters:
#   $from - FROM clause (with the word "FROM")
#
# Returns:
#   Arrayref of hashrefs, one hashref for each table in the order that
#   the tables appear, like:
#   (start code)
#   {
#     name           => 't2',  -- table's real name
#     alias          => 'b',   -- table's alias, if any
#     explicit_alias => 1,     -- if explicitly aliased with AS
#     join  => {               -- if joined to another table, all but first
#                              -- table are because comma implies INNER JOIN
#       to        => 't1',     -- table name on left side of join, if this is
#                              -- LEFT JOIN then this is the inner table, if
#                              -- RIGHT JOIN then this is outer table
#       type      => '',       -- left, right, inner, outer, cross, natural
#       condition => 'using',  -- on or using, if applicable
#       columns   => ['id'],   -- columns for USING condition, if applicable
#       ansi      => 1,        -- true of ANSI JOIN, i.e. true if not implicit
#                              -- INNER JOIN due to following a comma
#     },
#   },
#   {
#     name => 't3',
#     join => {
#       to        => 't2',
#       type      => 'left',
#       condition => 'on',     -- an ON condition is like a WHERE clause so
#       where     => [...]     -- this arrayref of predicates appears, see
#                              -- <parse_where()> for its structure
#     },
#   },
#  (end code)
sub parse_from {
   my ( $self, $from ) = @_;
   return unless $from;
   PTDEBUG && _d('Parsing FROM', $from);

   # Extract the column list from USING(col, ...) clauses else
   # the inner commas will be captured by $comma_join.
   my $using_cols;
   ($from, $using_cols) = $self->remove_using_columns($from);

   my $funcs;
   ($from, $funcs) = $self->remove_functions($from);

   # Table references in a FROM clause are separated either by commas
   # (comma/theta join, implicit INNER join) or the JOIN keyword (ansi
   # join).  JOIN can be preceded by other keywords like LEFT, RIGHT,
   # OUTER, etc.  There must be spaces before and after JOIN and its
   # keywords, but there does not have to be spaces before or after a
   # comma.  See http://dev.mysql.com/doc/refman/5.5/en/join.html
   my $comma_join = qr/(?>\s*,\s*)/;
   my $ansi_join  = qr/(?>
     \s+
     (?:(?:INNER|CROSS|STRAIGHT_JOIN|LEFT|RIGHT|OUTER|NATURAL)\s+)*
     JOIN
     \s+
   )/xi;

   my @tbls;     # all table refs, a hashref for each
   my $tbl_ref;  # current table ref hashref
   my $join;     # join info hahsref for current table ref
   foreach my $thing ( split /($comma_join|$ansi_join)/io, $from ) {
      # We shouldn't parse empty things.
      die "Error parsing FROM clause" unless $thing;

      # Strip leading and trailing spaces.
      $thing =~ s/^\s+//;
      $thing =~ s/\s+$//;
      PTDEBUG && _d('Table thing:', $thing);

      if ( $thing =~ m/\s+(?:ON|USING)\s+/i ) {
         PTDEBUG && _d("JOIN condition");
         # This join condition follows a JOIN (comma joins don't have
         # conditions).  It includes a table ref, ON|USING, and then
         # the value to ON|USING.
         my ($tbl_ref_txt, $join_condition_verb, $join_condition_value)
            = $thing =~ m/^(.+?)\s+(ON|USING)\s+(.+)/i;

         $tbl_ref = $self->parse_table_reference($tbl_ref_txt);

         $join->{condition} = lc $join_condition_verb;
         if ( $join->{condition} eq 'on' ) {
            # The value for ON can be, as the MySQL manual says, is just
            # like a WHERE clause.
            $join->{where} = $self->parse_where($join_condition_value, $funcs);
         }
         else { # USING
            # Although calling parse_columns() works, it's overkill.
            # This is not a columns def as in "SELECT col1, col2", it's
            # a simple csv list of column names without aliases, etc.
            $join->{columns} = $self->_parse_csv(shift @$using_cols);
         }
      }
      elsif ( $thing =~ m/(?:,|JOIN)/i ) {
         # A comma or JOIN signals the end of the current table ref and
         # the begining of the next table ref.  Save the current table ref.
         if ( $join ) {
            $tbl_ref->{join} = $join;
         }
         push @tbls, $tbl_ref;
         PTDEBUG && _d("Complete table reference:", Dumper($tbl_ref));

         # Reset vars for the next table ref.
         $tbl_ref = undef;
         $join    = {};

         # Next table ref becomes the current table ref.  It's joined to
         # the previous table ref either implicitly (comma join) or explicitly
         # (ansi join).
         $join->{to} = $tbls[-1]->{tbl};
         if ( $thing eq ',' ) {
            $join->{type} = 'inner';
            $join->{ansi} = 0;
         }
         else { # ansi join
            my $type = $thing =~ m/^(.+?)\s+JOIN$/i ? lc $1 : 'inner';
            $join->{type} = $type;
            $join->{ansi} = 1;
         }
      }
      else {
         # First table ref and comma-joined tables.
         $tbl_ref = $self->parse_table_reference($thing);
         PTDEBUG && _d('Table reference:', Dumper($tbl_ref));
      }
   }

   # Save the last table ref.  It's not completed in the loop above because
   # there's no comma or JOIN after it.
   if ( $tbl_ref ) {
      if ( $join ) {
         $tbl_ref->{join} = $join;
      }
      push @tbls, $tbl_ref;
      PTDEBUG && _d("Complete table reference:", Dumper($tbl_ref));
   }

   return \@tbls;
}

# Parse a table ref like "tbl", "tbl alias" or "tbl AS alias", where
# tbl can be optionally "db." qualified.  Also handles FORCE|USE|IGNORE
# INDEX hints.  Does not handle "FOR JOIN" hint because "JOIN" here gets
# confused with the "JOIN" thing in parse_from().
sub parse_table_reference {
   my ( $self, $tbl_ref ) = @_;
   return unless $tbl_ref;
   PTDEBUG && _d('Parsing table reference:', $tbl_ref);
   my %tbl;

   # First, check for an index hint.  Remove and save it if present.
   # This can't be included in the $table_ident regex because, for example,
   # `tbl` FORCE INDEX (foo), makes FORCE look like an implicit alias.
   if ( $tbl_ref =~ s/
         \s+(
            (?:FORCE|USE|INGORE)\s
            (?:INDEX|KEY)
            \s*\([^\)]+\)\s*
         )//xi)
   {
      $tbl{index_hint} = $1;
      PTDEBUG && _d('Index hint:', $tbl{index_hint});
   }

   if ( $tbl_ref =~ m/$table_ident/ ) {
      my ($db_tbl, $as, $alias) = ($1, $2, $3); # XXX
      my $ident_struct = $self->parse_identifier('table', $db_tbl);
      $alias =~ s/`//g if $alias;
      @tbl{keys %$ident_struct} = values %$ident_struct;
      $tbl{explicit_alias} = 1 if $as;
      $tbl{alias}          = $alias if $alias;
   }
   else {
      die "Table ident match failed";  # shouldn't happen
   }

   return \%tbl;
}
{
   no warnings;  # Why? See same line above.
   *parse_into   = \&parse_from;
   *parse_tables = \&parse_from;
}

# This is not your traditional parser, but it works for simple to rather
# complex cases, with a few noted and intentional limitations.  First,
# the limitations:
#
#   * probably doesn't handle every possible operator (see $op)
#   * doesn't care about grouping with parentheses
#   * not "fully" tested because the possibilities are infinite
#
# It works in four steps; let's take this WHERE clause as an example:
# 
#   i="x and y" or j in ("and", "or") and x is not null or a between 1 and 10 and sz="this 'and' foo"
#
# The first step splits the string on and|or, the only two keywords I'm
# aware of that join the separate predicates.  This step doesn't care if
# and|or is really between two predicates or in a string or something else.
# The second step is done while the first step is being done: check predicate
# "fragments" (from step 1) for operators; save which ones have and don't
# have at least one operator.  So the result of step 1 and 2 is:
#
#   PREDICATE FRAGMENT                OPERATOR
#   ================================  ========
#   i="x                              Y
#   and y"                            N
#   or j in ("                        Y
#   and", "                           N
#   or")                              N
#   and x is not null                 Y
#   or a between 1                    Y
#   and 10                            N
#   and sz="this '                    Y
#   and' foo"                         N
#
# The third step runs through the list of pred frags backwards and joins
# the current frag to the preceding frag if it does not have an operator.
# The result is:
# 
#   PREDICATE FRAGMENT                OPERATOR
#   ================================  ========
#   i="x and y"                       Y
#                                     N
#   or j in ("and", "or")             Y
#                                     N
#                                     N
#   and x is not null                 Y
#   or a between 1 and 10             Y
#                                     N
#   and sz="this 'and' foo"           Y
#                                     N
#
# The fourth step is similar but not shown: pred frags with unbalanced ' or "
# are joined to the preceding pred frag.  This fixes cases where a pred frag
# has multiple and|or in a string value; e.g. "foo and bar or dog".
# 
# After the pred frags are complete, the parts of these predicates are parsed
# and returned in an arrayref of hashrefs like:
#
#   {
#     predicate => 'and',
#     column    => 'id',
#     operator  => '>=',
#     value     => '42',
#   }
#
# Invalid predicates, or valid ones that we can't parse,  will cause
# the sub to die.
sub parse_where {
   my ( $self, $where, $functions ) = @_;
   return unless $where;
   PTDEBUG && _d("Parsing WHERE", $where);

   # Not all the operators listed at
   # http://dev.mysql.com/doc/refman/5.1/en/non-typed-operators.html
   # are supported.  E.g. - (minus) is an op but does it ever show up
   # in a where clause?  "col-3=2" is valid (where col=5), but we're
   # not interested in weird stuff like that.
   my $op_symbol = qr/
      (?:
       <=(?:>)?
      |>=
      |<>
      |!=
      |<
      |>
      |=
   )/xi;
   my $op_verb = qr/
      (?:
          (?:(?:NOT\s)?LIKE)
         |(?:IS(?:\sNOT\s)?)
         |(?:(?:\sNOT\s)?BETWEEN)
         |(?:(?:NOT\s)?IN)
      )
   /xi;
   my $op_pat = qr/
   (
      (?>
          (?:$op_symbol)  # don't need spaces around the symbols, e.g.: col=1
         |(?:\s+$op_verb) # must have space before verb op, e.g.: col LIKE ...
      )
   )/x;

   # Step 1 and 2: split on and|or and look for operators.
   my $offset = 0;
   my $pred   = "";
   my @pred;
   my @has_op;
   while ( $where =~ m/\b(and|or)\b/gi ) {
      my $pos = (pos $where) - (length $1);  # pos at and|or, not after

      $pred = substr $where, $offset, ($pos-$offset);
      push @pred, $pred;
      push @has_op, $pred =~ m/$op_pat/o ? 1 : 0;

      $offset = $pos;
   }
   # Final predicate fragment: last and|or to end of string.
   $pred = substr $where, $offset;
   push @pred, $pred;
   push @has_op, $pred =~ m/$op_pat/o ? 1 : 0;
   PTDEBUG && _d("Predicate fragments:", Dumper(\@pred));
   PTDEBUG && _d("Predicate frags with operators:", @has_op);

   # Step 3: join pred frags without ops to preceding pred frag.
   my $n = scalar @pred - 1;
   for my $i ( 1..$n ) {
      $i   *= -1;
      my $j = $i - 1;  # preceding pred frag

      # Two constants in a row, like "TRUE or FALSE", are a special case.
      # The current pred ($i) will not have an op but in this case it's
      # not a continuation of the preceding pred ($j) so we don't want to
      # join them.  And there's a special case within this special case:
      # "BETWEEN 1 AND 10".  _is_constant() strips leading AND or OR so
      # 10 is going to look like an independent constant but really it's
      # part of the BETWEEN op, so this whole special check is skipped
      # if the preceding pred contains BETWEEN.  Yes, parsing SQL is tricky.
      next if $pred[$j] !~ m/\s+between\s+/i  && $self->_is_constant($pred[$i]);

      if ( !$has_op[$i] ) {
         $pred[$j] .= $pred[$i];
         $pred[$i]  = undef;
      }
   }
   PTDEBUG && _d("Predicate fragments joined:", Dumper(\@pred));

   # Step 4: join pred frags with unbalanced ' or " to preceding pred frag.
   for my $i ( 0..@pred ) {
      $pred = $pred[$i];
      next unless defined $pred;
      my $n_single_quotes = ($pred =~ tr/'//);
      my $n_double_quotes = ($pred =~ tr/"//);
      if ( ($n_single_quotes % 2) || ($n_double_quotes % 2) ) {
         $pred[$i]     .= $pred[$i + 1];
         $pred[$i + 1]  = undef;
      }
   }
   PTDEBUG && _d("Predicate fragments balanced:", Dumper(\@pred));

   # Parse, clean up and save the complete predicates.
   my @predicates;
   foreach my $pred ( @pred ) {
      next unless defined $pred;
      $pred =~ s/^\s+//;
      $pred =~ s/\s+$//;
      my $conj;
      if ( $pred =~ s/^(and|or)\s+//i ) {
         $conj = lc $1;
      }
      my ($col, $op, $val) = $pred =~ m/^(.+?)$op_pat(.+)$/o;
      if ( !$col || !$op ) {
         if ( $self->_is_constant($pred) ) {
            $val = lc $pred;
         }
         else {
            die "Failed to parse WHERE condition: $pred";
         }
      }

      # Remove whitespace and lowercase some keywords.
      if ( $col ) {
         $col =~ s/\s+$//;
         $col =~ s/^\(+//;  # no unquoted column name begins with (
      }
      if ( $op ) {
         $op  =  lc $op;
         $op  =~ s/^\s+//;
         $op  =~ s/\s+$//;
      }
      $val =~ s/^\s+//;
      
      # No unquoted value ends with ) except FUNCTION(...)
      if ( ($op || '') !~ m/IN/i && $val !~ m/^\w+\([^\)]+\)$/ ) {
         $val =~ s/\)+$//;
      }

      if ( $val =~ m/NULL|TRUE|FALSE/i ) {
         $val = lc $val;
      }

      if ( $functions ) {
         $col = shift @$functions if $col =~ m/__FUNC\d+__/;
         $val = shift @$functions if $val =~ m/__FUNC\d+__/;
      }

      push @predicates, {
         predicate => $conj,
         left_arg  => $col,
         operator  => $op,
         right_arg => $val,
      };
   }

   return \@predicates;
}

# Returns true if the value is a constant.  Constants are TRUE, FALSE,
# and any signed number.  A leading AND or OR keyword is removed first.
sub _is_constant {
   my ( $self, $val ) = @_;
   return 0 unless defined $val;
   $val =~ s/^\s*(?:and|or)\s+//;
   return
      $val =~ m/^\s*(?:TRUE|FALSE)\s*$/i || $val =~ m/^\s*-?\d+\s*$/ ? 1 : 0;
}

sub parse_having {
   my ( $self, $having ) = @_;
   # TODO
   return $having;
}

# GROUP BY {col_name | expr | position} [ASC | DESC], ... [WITH ROLLUP]
sub parse_group_by {
   my ( $self, $group_by ) = @_;
   return unless $group_by;
   PTDEBUG && _d('Parsing GROUP BY', $group_by);

   # Remove special "WITH ROLLUP" clause so we're left with a simple csv list.
   my $with_rollup = $group_by =~ s/\s+WITH ROLLUP\s*//i;

   # Parse the identifers.
   my $idents = $self->parse_identifiers( $self->_parse_csv($group_by) );

   $idents->{with_rollup} = 1 if $with_rollup;

   return $idents;
}

# [ORDER BY {col_name | expr | position} [ASC | DESC], ...]
sub parse_order_by {
   my ( $self, $order_by ) = @_;
   return unless $order_by;
   PTDEBUG && _d('Parsing ORDER BY', $order_by);
   my $idents = $self->parse_identifiers( $self->_parse_csv($order_by) );
   return $idents;
}

# [LIMIT {[offset,] row_count | row_count OFFSET offset}]
sub parse_limit {
   my ( $self, $limit ) = @_;
   return unless $limit;
   my $struct = {
      row_count => undef,
   };
   if ( $limit =~ m/(\S+)\s+OFFSET\s+(\S+)/i ) {
      $struct->{explicit_offset} = 1;
      $struct->{row_count}       = $1;
      $struct->{offset}          = $2;
   }
   else {
      my ($offset, $cnt) = $limit =~ m/(?:(\S+),\s+)?(\S+)/i;
      $struct->{row_count} = $cnt;
      $struct->{offset}    = $offset if defined $offset;
   }
   return $struct;
}

# Parses the list of values after, e.g., INSERT tbl VALUES (...), (...).
# Does not currently parse each set of values; it just splits the list.
sub parse_values {
   my ( $self, $values ) = @_;
   return unless $values;
   $values =~ s/^\s*\(//;
   $values =~ s/\s*\)//;
   my $vals = $self->_parse_csv(
      $values,
      quoted_values => 1,
      remove_quotes => 0,
   );
   return $vals;
}

sub parse_set {
   my ( $self, $set ) = @_;
   PTDEBUG && _d("Parse SET", $set);
   return unless $set;
   my $vals = $self->_parse_csv($set);
   return unless $vals && @$vals;

   my @set;
   foreach my $col_val ( @$vals ) {
      # Do not remove quotes around the val because quotes let us determine
      # the value's type.  E.g. tbl might be a table, but "tbl" is a string,
      # and NOW() is the function, but 'NOW()' is a string.
      my ($col, $val)  = $col_val =~ m/^([^=]+)\s*=\s*(.+)/;
      my $ident_struct = $self->parse_identifier('column', $col);
      my $set_struct   = {
         %$ident_struct,
         value => $val,
      };
      PTDEBUG && _d("SET:", Dumper($set_struct));
      push @set, $set_struct;
   }
   return \@set;
}

# Split any comma-separated list of values, removing leading
# and trailing spaces.
sub _parse_csv {
   my ( $self, $vals, %args ) = @_;
   return unless $vals;

   my @vals;
   if ( $args{quoted_values} ) {
      # If the vals are quoted, then they can contain commas, like:
      # "hello, world!", 'batman'.  If only we could use Text::CSV,
      # then I wouldn't write yet another csv parser to handle this,
      # but Maatkit doesn't like package dependencies, so here's my
      # light implementation of this classic problem.
      my $quote_char   = '';
      VAL:
      foreach my $val ( split(',', $vals) ) {
         PTDEBUG && _d("Next value:", $val);
         # If there's a quote char, then this val is the rest of a previously
         # quoted and split value.
         if ( $quote_char ) {
            PTDEBUG && _d("Value is part of previous quoted value");
            # split() removed the comma inside the quoted value,
            # so add it back else "hello, world" is incorrectly
            # returned as "hello world".
            $vals[-1] .= ",$val";

            # Quoted and split value is complete when a val ends with the
            # same quote char that began the split value.
            if ( $val =~ m/[^\\]*$quote_char$/ ) {
               if ( $args{remove_quotes} ) {
                  $vals[-1] =~ s/^\s*$quote_char//;
                  $vals[-1] =~ s/$quote_char\s*$//;
               }
               PTDEBUG && _d("Previous quoted value is complete:", $vals[-1]);
               $quote_char = '';
            }

            next VAL;
         }

         # Start of new value so strip leading spaces but not trailing
         # spaces yet because if the next check determines that this is
         # a quoted and split val, then trailing space is actually space
         # inside the quoted val, so we want to preserve it.
         $val =~ s/^\s+//;

         # A value is quoted *and* split (because there's a comma in the
         # quoted value) if the vale begins with a quote char and does not
         # end with that char.  E.g.: "foo but not "foo".  The val "foo is
         # the first part of the split value, e.g. "foo, bar".
         if ( $val =~ m/^(['"])/ ) {
            PTDEBUG && _d("Value is quoted");
            $quote_char = $1;  # XXX
            if ( $val =~ m/.$quote_char$/ ) {
               PTDEBUG && _d("Value is complete");
               $quote_char = '';
               if ( $args{remove_quotes} ) {
                  $vals[-1] =~ s/^\s*$quote_char//;
                  $vals[-1] =~ s/$quote_char\s*$//;
               }
            }
            else {
               PTDEBUG && _d("Quoted value is not complete");
            }
         }
         else {
            $val =~ s/\s+$//;
         }

         # Save complete value (e.g. foo or "foo" without the quotes),
         # or save the first part of a quoted and split value; the rest
         # of such a value will be joined back above.
         PTDEBUG && _d("Saving value", ($quote_char ? "fragment" : ""));
         push @vals, $val;
      }
   }
   else {
      @vals = map { s/^\s+//; s/\s+$//; $_ } split(',', $vals);
   }

   return \@vals;
}
{
   no warnings;  # Why? See same line above.
   *parse_on_duplicate = \&_parse_csv;
}

sub parse_columns {
   my ( $self, $cols ) = @_;
   PTDEBUG && _d('Parsing columns list:', $cols);

   my @cols;
   pos $cols = 0;
   while (pos $cols < length $cols) {
      if ($cols =~ m/\G\s*$column_ident\s*(?>,|\Z)/gcxo) {
         my ($db_tbl_col, $as, $alias) = ($1, $2, $3); # XXX
         my $ident_struct = $self->parse_identifier('column', $db_tbl_col);
         $alias =~ s/`//g if $alias;
         my $col_struct = {
            %$ident_struct,
            ($as    ? (explicit_alias => 1)      : ()),
            ($alias ? (alias          => $alias) : ()),
         };
         push @cols, $col_struct;
      }
      else {
         die "Column ident match failed";  # shouldn't happen
      }
   }

   return \@cols;
}

# Remove subqueries from query, return modified query and list of subqueries.
# Each subquery is replaced with the special token __SQn__ where n is the
# subquery's ID.  Subqueries are parsed and removed in to out, last to first;
# i.e. the last, inner-most subquery is ID 0 and the first, outermost
# subquery has the greatest ID.  Each subquery ID corresponds to its index in
# the list of returned subquery hashrefs after the modified query.  __SQ2__
# is subqueries[2].  Each hashref is like:
#   * query    Subquery text
#   * context  scalar, list or identifier
#   * nested   (optional) 1 if nested
# This sub does not handle UNION and it expects to that subqueries start
# with "(SELECT ".  See SQLParser.t for examples.
sub remove_subqueries {
   my ( $self, $query ) = @_;

   # Find starting pos of all subqueries.
   my @start_pos;
   while ( $query =~ m/(\(SELECT )/gi ) {
      my $pos = (pos $query) - (length $1);
      push @start_pos, $pos;
   }

   # Starting with the inner-most, last subquery, find ending pos of
   # all subqueries.  This is done by counting open and close parentheses
   # until all are closed.  The last closing ) should close the ( that
   # opened the subquery.  No sane regex can help us here for cases like:
   # (select max(id) from t where col in(1,2,3) and foo='(bar)').
   @start_pos = reverse @start_pos;
   my @end_pos;
   for my $i ( 0..$#start_pos ) {
      my $closed = 0;
      pos $query = $start_pos[$i];
      while ( $query =~ m/([\(\)])/cg ) {
         my $c = $1;
         $closed += ($c eq '(' ? 1 : -1);
         last unless $closed;
      }
      push @end_pos, pos $query;
   }

   # Replace each subquery with a __SQn__ token.
   my @subqueries;
   my $len_adj = 0;
   my $n    = 0;
   for my $i ( 0..$#start_pos ) {
      PTDEBUG && _d('Query:', $query);
      my $offset = $start_pos[$i];
      my $len    = $end_pos[$i] - $start_pos[$i] - $len_adj;
      PTDEBUG && _d("Subquery $n start", $start_pos[$i],
            'orig end', $end_pos[$i], 'adj', $len_adj, 'adj end',
            $offset + $len, 'len', $len);

      my $struct   = {};
      my $token    = '__SQ' . $n . '__';
      my $subquery = substr($query, $offset, $len, $token);
      PTDEBUG && _d("Subquery $n:", $subquery);

      # Adjust len for next outer subquery.  This is required because the
      # subqueries' start/end pos are found relative to one another, so
      # when a subquery is replaced with its shorter __SQn__ token the end
      # pos for the other subqueries decreases.  The token is shorter than
      # any valid subquery so the end pos should only decrease.
      my $outer_start = $start_pos[$i + 1];
      my $outer_end   = $end_pos[$i + 1];
      if (    $outer_start && ($outer_start < $start_pos[$i])
           && $outer_end   && ($outer_end   > $end_pos[$i]) ) {
         PTDEBUG && _d("Subquery $n nested in next subquery");
         $len_adj += $len - length $token;
         $struct->{nested} = $i + 1;
      }
      else {
         PTDEBUG && _d("Subquery $n not nested");
         $len_adj = 0;
         if ( $subqueries[-1] && $subqueries[-1]->{nested} ) {
            PTDEBUG && _d("Outermost subquery");
         }
      }

      # Get subquery context: scalar, list or identifier.
      if ( $query =~ m/(?:=|>|<|>=|<=|<>|!=|<=>)\s*$token/ ) {
         $struct->{context} = 'scalar';
      }
      elsif ( $query =~ m/\b(?:IN|ANY|SOME|ALL|EXISTS)\s*$token/i ) {
         # Add ( ) around __SQn__ for things like "IN(__SQn__)"
         # unless they're already there.
         if ( $query !~ m/\($token\)/ ) {
            $query =~ s/$token/\($token\)/;
            $len_adj -= 2 if $struct->{nested};
         }
         $struct->{context} = 'list';
      }
      else {
         # If the subquery is not preceded by an operator (=, >, etc.)
         # or IN(), EXISTS(), etc. then it should be an indentifier,
         # either a derived table or column.
         $struct->{context} = 'identifier';
      }
      PTDEBUG && _d("Subquery $n context:", $struct->{context});

      # Remove ( ) around subquery so it can be parsed by a parse_TYPE sub.
      $subquery =~ s/^\s*\(//;
      $subquery =~ s/\s*\)\s*$//;

      # Save subquery to struct after modifications above.
      $struct->{query} = $subquery;
      push @subqueries, $struct;
      $n++;
   }

   return $query, @subqueries;
}

sub remove_using_columns {
   my ($self, $from) = @_;
   return unless $from;
   PTDEBUG && _d('Removing cols from USING clauses');
   my $using = qr/
      \bUSING
      \s*
      \(
         ([^\)]+)
      \)
   /xi;
   my @cols;
   $from =~ s/$using/push @cols, $1; "USING ($#cols)"/eg;
   PTDEBUG && _d('FROM:', $from, Dumper(\@cols));
   return $from, \@cols;
}

sub replace_function {
   my ($func, $funcs) = @_;
   my ($func_name) = $func =~ m/^(\w+)/;
   if ( !$ignore_function{uc $func_name} ) {
      my $n = scalar @$funcs;
      push @$funcs, $func;
      return "__FUNC${n}__";
   }
   return $func;
}

sub remove_functions {
   my ($self, $clause) = @_;
   return unless $clause;
   PTDEBUG && _d('Removing functions from clause:', $clause);
   my @funcs;
   $clause =~ s/$function_ident/replace_function($1, \@funcs)/eg;
   PTDEBUG && _d('Function-stripped clause:', $clause, Dumper(\@funcs));
   return $clause, \@funcs;
}

# Sub: parse_identifiers
#   Parse an arrayref of identifiers into their parts.  Identifiers can be
#   column names (optionally qualified), expressions, or constants.
#   GROUP BY and ORDER BY specify a list of identifiers.
#
# Parameters:
#   $idents - Arrayref of indentifiers
#
# Returns:
#   Arrayref of hashes with each identifier's parts, depending on what kind
#   of identifier it is.
sub parse_identifiers {
   my ( $self, $idents ) = @_;
   return unless $idents;
   PTDEBUG && _d("Parsing identifiers");

   my @ident_parts;
   foreach my $ident ( @$idents ) {
      PTDEBUG && _d("Identifier:", $ident);
      my $parts = {};

      if ( $ident =~ s/\s+(ASC|DESC)\s*$//i ) {
         $parts->{sort} = uc $1;  # XXX
      }

      if ( $ident =~ m/^\d+$/ ) {      # Position like 5
         PTDEBUG && _d("Positional ident");
         $parts->{position} = $ident;
      }
      elsif ( $ident =~ m/^\w+\(/ ) {  # Function like MIN(col)
         PTDEBUG && _d("Expression ident");
         my ($func, $expr) = $ident =~ m/^(\w+)\(([^\)]*)\)/;
         $parts->{function}   = uc $func;
         $parts->{expression} = $expr if $expr;
      }
      else {                           # Ref like (table.)column
         PTDEBUG && _d("Table/column ident");
         my ($tbl, $col)  = $self->split_unquote($ident);
         $parts->{table}  = $tbl if $tbl;
         $parts->{column} = $col;
      }
      push @ident_parts, $parts;
   }

   return \@ident_parts;
}

sub parse_identifier {
   my ( $self, $type, $ident ) = @_;
   return unless $type && $ident;
   PTDEBUG && _d("Parsing", $type, "identifier:", $ident);

   my ($func, $expr);
   if ( $ident =~ m/^\w+\(/ ) {  # Function like MIN(col)
      ($func, $expr) = $ident =~ m/^(\w+)\(([^\)]*)\)/;
      PTDEBUG && _d('Function', $func, 'arg', $expr);
      return { col => $ident } unless $expr;  # NOW()
      $ident = $expr;  # col from MAX(col)
   }

   my %ident_struct;
   my @ident_parts = map { s/`//g; $_; } split /[.]/, $ident;
   if ( @ident_parts == 3 ) {
      @ident_struct{qw(db tbl col)} = @ident_parts;
   }
   elsif ( @ident_parts == 2 ) {
      my @parts_for_type = $type eq 'column' ? qw(tbl col)
                         : $type eq 'table'  ? qw(db  tbl)
                         : die "Invalid identifier type: $type";
      @ident_struct{@parts_for_type} = @ident_parts;
   }
   elsif ( @ident_parts == 1 ) {
      my $part = $type eq 'column' ? 'col' : 'tbl';
      @ident_struct{($part)} = @ident_parts;
   }
   else {
      die "Invalid number of parts in $type reference: $ident";
   }
   
   if ( $self->{Schema} ) {
      if ( $type eq 'column' && (!$ident_struct{tbl} || !$ident_struct{db}) ) {
         my $qcol = $self->{Schema}->find_column(%ident_struct);
         if ( $qcol && @$qcol == 1 ) {
            @ident_struct{qw(db tbl)} = @{$qcol->[0]}{qw(db tbl)};
         }
      }
      elsif ( !$ident_struct{db} ) {
         my $qtbl = $self->{Schema}->find_table(%ident_struct);
         if ( $qtbl && @$qtbl == 1 ) {
            $ident_struct{db} = $qtbl->[0];
         }
      }
   }

   if ( $func ) {
      $ident_struct{func} = uc $func;
   }

   PTDEBUG && _d($type, "identifier struct:", Dumper(\%ident_struct));
   return \%ident_struct;
}

# Sub: split_unquote
#   Split and unquote a table name.  The table name can be database-qualified
#   or not, like `db`.`table`.  The table name can be backtick-quoted or not.
#
# Parameters:
#   $db_tbl     - Table name
#   $default_db - Default database name to return if $db_tbl is not
#                 database-qualified
#
# Returns:
#   Array: unquoted database (possibly undef), unquoted table
sub split_unquote {
   my ( $self, $db_tbl, $default_db ) = @_;
   $db_tbl =~ s/`//g;
   my ( $db, $tbl ) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   return ($db, $tbl);
}

# Sub: is_identifier
#   Determine if something is a schema object identifier.
#   E.g.: `tbl` is an identifier, but "tbl" is a string and 1 is a number.
#   See <http://dev.mysql.com/doc/refman/5.1/en/identifiers.html>
#
# Parameters:
#   $thing - Name of something, including any quoting as it appears in a query.
#
# Returns:
#   True of $thing is an identifier, else false.
sub is_identifier {
   my ( $self, $thing ) = @_;

   # Nothing is not an ident.
   return 0 unless $thing;

   # Tables, columns, FUNCTIONS(), etc. cannot be 'quoted' or "quoted"
   # because that would make them strings, not idents.
   return 0 if $thing =~ m/\s*['"]/;

   # Numbers, ints or floats, are not identifiers.
   return 0 if $thing =~ m/^\s*\d+(?:\.\d+)?\s*$/;

   # Keywords are not identifiers.
   return 0 if $thing =~ m/^\s*(?>
       NULL
      |DUAL
   )\s*$/xi;

   # The column ident really matches everything: db, db.tbl, db.tbl.col,
   # function(), @@var, etc.
   return 1 if $thing =~ m/^\s*$column_ident\s*$/;

   # If the thing isn't quoted and doesn't match our ident pattern, then
   # it's probably not an ident.
   return 0;
}

sub set_Schema {
   my ( $self, $sq ) = @_;
   $self->{Schema} = $sq;
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
# End SQLParser package
# ###########################################################################
