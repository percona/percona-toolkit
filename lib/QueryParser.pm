# This program is copyright 2008-2011 Percona Ireland Ltd.
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
# QueryParser package
# ###########################################################################
{
# Package: QueryParser
# QueryParser extracts parts of SQL statements, like table lists and subqueries.
# This package differs from SQLParser because it only extracts from a query
# what is needed and only when that can be accomplished rather simply.  By
# contrast, SQLParser parses the entire SQL statement no matter the complexity.
package QueryParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

our $tbl_ident = qr/(?:`[^`]+`|\w+)(?:\.(?:`[^`]+`|\w+))?/;
# This regex finds things that look like database.table identifiers, based on
# their proximity to keywords.  (?<!KEY\s) is a workaround for ON DUPLICATE KEY
# UPDATE, which is usually followed by a column name.
our $tbl_regex = qr{
         \b(?:FROM|JOIN|(?<!KEY\s)UPDATE|INTO) # Words that precede table names
         \b\s*
         \(?                                   # Optional paren around tables
         # Capture the identifier and any number of comma-join identifiers that
         # follow it, optionally with aliases with or without the AS keyword
         ($tbl_ident
            (?: (?:\s+ (?:AS\s+)? \w+)?, \s*$tbl_ident )*
         )
      }xio;
# This regex is meant to match "derived table" queries, of the form
# .. from ( select ...
# .. join ( select ...
# .. bar join foo, ( select ...
# Unfortunately it'll also match this:
# select a, b, (select ...
our $has_derived = qr{
      \b(?:FROM|JOIN|,)
      \s*\(\s*SELECT
   }xi;

# http://dev.mysql.com/doc/refman/5.1/en/sql-syntax-data-definition.html
# We treat TRUNCATE as a dds but really it's a data manipulation statement.
our $data_def_stmts = qr/(?:CREATE|ALTER|TRUNCATE|DROP|RENAME)/i;

# http://dev.mysql.com/doc/refman/5.1/en/sql-syntax-data-manipulation.html
# Data manipulation statements.
our $data_manip_stmts = qr/(?:INSERT|UPDATE|DELETE|REPLACE)/i;

sub new {
   my ( $class ) = @_;
   bless {}, $class;
}

# Returns a list of table names found in the query text.
sub get_tables {
   my ( $self, $query ) = @_;
   return unless $query;
   PTDEBUG && _d('Getting tables for', $query);

   # Handle CREATE, ALTER, TRUNCATE and DROP TABLE.
   my ( $ddl_stmt ) = $query =~ m/^\s*($data_def_stmts)\b/i;
   if ( $ddl_stmt ) {
      PTDEBUG && _d('Special table type:', $ddl_stmt);
      $query =~ s/IF\s+(?:NOT\s+)?EXISTS//i;
      if ( $query =~ m/$ddl_stmt DATABASE\b/i ) {
         # Handles CREATE DATABASE, not to be confused with CREATE TABLE.
         PTDEBUG && _d('Query alters a database, not a table');
         return ();
      }
      if ( $ddl_stmt =~ m/CREATE/i && $query =~ m/$ddl_stmt\b.+?\bSELECT\b/i ) {
         # Handle CREATE TABLE ... SELECT.  In this case, the real tables
         # come from the SELECT, not the CREATE.
         my ($select) = $query =~ m/\b(SELECT\b.+)/is;
         PTDEBUG && _d('CREATE TABLE ... SELECT:', $select);
         return $self->get_tables($select);
      }
      my ($tbl) = $query =~ m/TABLE\s+($tbl_ident)(\s+.*)?/i;
      PTDEBUG && _d('Matches table:', $tbl);
      return ($tbl);
   }

   # These keywords may appear between UPDATE or SELECT and the table refs.
   # They need to be removed so that they are not mistaken for tables.
   $query =~ s/(?:LOW_PRIORITY|IGNORE|STRAIGHT_JOIN|DELAYED)\s+/ /ig;

   # Another special case: LOCK TABLES tbl [[AS] alias] READ|WRITE, etc.
   # We strip the LOCK TABLES stuff and append "FROM" to fake a SELECT
   # statement and allow $tbl_regex to match below.
   if ( $query =~ s/^\s*LOCK TABLES\s+//i ) {
      PTDEBUG && _d('Special table type: LOCK TABLES');
      $query =~ s/\s+(?:READ(?:\s+LOCAL)?|WRITE)\s*//gi;
      PTDEBUG && _d('Locked tables:', $query);
      $query = "FROM $query";
   }

   $query =~ s/\\["']//g;   # quoted strings
   $query =~ s/".*?"/?/sg;  # quoted strings
   $query =~ s/'.*?'/?/sg;  # quoted strings

   # INSERT and REPLACE without INTO
   # https://bugs.launchpad.net/percona-toolkit/+bug/984053
   if ( $query =~ m/\A\s*(?:INSERT|REPLACE)(?!\s+INTO)/i ) {
      # Add INTO so the reset of the code work as usual.
      $query =~ s/\A\s*((?:INSERT|REPLACE))\s+/$1 INTO /i;
   }

   if ( $query =~ m/\A\s*LOAD DATA/i ) {
      my ($tbl) = $query =~ m/INTO TABLE\s+(\S+)/i;
      return $tbl;
   }

   my @tables;
   foreach my $tbls ( $query =~ m/$tbl_regex/gio ) {
      PTDEBUG && _d('Match tables:', $tbls);

      # Some queries coming from certain ORM systems will have superfluous
      # parens around table names, like SELECT * FROM (`mytable`);  We match
      # these so the table names can be extracted more simply with regexes.  But
      # in case of subqueries, this can cause us to match SELECT as a table
      # name, for example, in SELECT * FROM (SELECT ....) AS X;  It's possible
      # that SELECT is really a table name, but so unlikely that we just skip
      # this case.
      next if $tbls =~ m/\ASELECT\b/i;

      foreach my $tbl ( split(',', $tbls) ) {
         # Remove implicit or explicit (AS) alias.
         $tbl =~ s/\s*($tbl_ident)(\s+.*)?/$1/gio;

         # Sanity check for cases like when a column is named `from`
         # and the regex matches junk.  Instead of complex regex to
         # match around these rarities, this simple check will save us.
         if ( $tbl !~ m/[a-zA-Z]/ ) {
            PTDEBUG && _d('Skipping suspicious table name:', $tbl);
            next;
         }

         push @tables, $tbl;
      }
   }
   return @tables;
}

# Returns true if it sees what looks like a "derived table", e.g. a subquery in
# the FROM clause.
sub has_derived_table {
   my ( $self, $query ) = @_;
   # See the $tbl_regex regex above.
   my $match = $query =~ m/$has_derived/;
   PTDEBUG && _d($query, 'has ' . ($match ? 'a' : 'no') . ' derived table');
   return $match;
}

# Return a data structure of tables/databases and the name they're aliased to.
# Given the following query, SELECT * FROM db.tbl AS foo; the structure is:
# { TABLE => { foo => tbl }, DATABASE => { tbl => db } }
# If $list is true, then a flat list of tables found in the query is returned
# instead.  This is used for things that want to know what tables the query
# touches, but don't care about aliases.
sub get_aliases {
   my ( $self, $query, $list ) = @_;

   # This is the basic result every query must return.
   my $result = {
      DATABASE => {},
      TABLE    => {},
   };
   return $result unless $query;

   # These keywords may appear between UPDATE or SELECT and the table refs.
   # They need to be removed so that they are not mistaken for tables.
   $query =~ s/ (?:LOW_PRIORITY|IGNORE|STRAIGHT_JOIN)//ig;

   # These keywords may appear before JOIN. They need to be removed so
   # that they are not mistaken for implicit aliases of the preceding table.
   $query =~ s/ (?:INNER|OUTER|CROSS|LEFT|RIGHT|NATURAL)//ig;

   # Get the table references clause and the keyword that starts the clause.
   # See the comments below for why we need the starting keyword.
   my @tbl_refs;
   my ($tbl_refs, $from) = $query =~ m{
      (
         (FROM|INTO|UPDATE)\b\s*   # Keyword before table refs
         .+?                       # Table refs
      )
      (?:\s+|\z)                   # If the query does not end with the table
                                   # refs then there must be at least 1 space
                                   # between the last tbl ref and the next
                                   # keyword
      (?:WHERE|ORDER|LIMIT|HAVING|SET|VALUES|\z) # Keyword after table refs
   }ix;

   if ( $tbl_refs ) {

      if ( $query =~ m/^(?:INSERT|REPLACE)/i ) {
         # Remove optional columns def from INSERT/REPLACE.
         $tbl_refs =~ s/\([^\)]+\)\s*//;
      }

      PTDEBUG && _d('tbl refs:', $tbl_refs);

      # These keywords precede a table ref. They signal the start of a table
      # ref, but to know where the table ref ends we need the after tbl ref
      # keywords below.
      my $before_tbl = qr/(?:,|JOIN|\s|$from)+/i;

      # These keywords signal the end of a table ref and either 1) the start
      # of another table ref, or 2) the start of an ON|USING part of a JOIN
      # clause (which we want to skip over), or 3) the end of the string (\z).
      # We need these after tbl ref keywords so that they are not mistaken
      # for implicit aliases of the preceding table.
      my $after_tbl  = qr/(?:,|JOIN|ON|USING|\z)/i;

      # This is required for cases like:
      #    FROM t1 JOIN t2 ON t1.col1=t2.col2 JOIN t3 ON t2.col3 = t3.col4
      # Because spaces may precede a tbl and a tbl may end with \z, then
      # t3.col4 will match as a table. However, t2.col3=t3.col4 will not match.
      $tbl_refs =~ s/ = /=/g;

      while (
         $tbl_refs =~ m{
            $before_tbl\b\s*
               ( ($tbl_ident) (?:\s+ (?:AS\s+)? (\w+))? )
            \s*$after_tbl
         }xgio )
      {
         my ( $tbl_ref, $db_tbl, $alias ) = ($1, $2, $3);
         PTDEBUG && _d('Match table:', $tbl_ref);
         push @tbl_refs, $tbl_ref;
         $alias = $self->trim_identifier($alias);

         # Handle subqueries.
         if ( $tbl_ref =~ m/^AS\s+\w+/i ) {
            # According to the manual
            # http://dev.mysql.com/doc/refman/5.0/en/unnamed-views.html:
            # "The [AS] name  clause is mandatory, because every table in a
            # FROM clause must have a name."
            # So if the tbl ref begins with 'AS', then we probably have a
            # subquery.
            PTDEBUG && _d('Subquery', $tbl_ref);
            $result->{TABLE}->{$alias} = undef;
            next;
         }

         my ( $db, $tbl ) = $db_tbl =~ m/^(?:(.*?)\.)?(.*)/;
         $db  = $self->trim_identifier($db);
         $tbl = $self->trim_identifier($tbl);
         $result->{TABLE}->{$alias || $tbl} = $tbl;
         $result->{DATABASE}->{$tbl}        = $db if $db;
      }
   }
   else {
      PTDEBUG && _d("No tables ref in", $query);
   }

   if ( $list ) {
      # Return raw text of the tbls without aliases, instead of identifier
      # mappings.  Include all identifier quotings and such.
      return \@tbl_refs;
   }
   else {
      return $result;
   }
}

# Splits a compound statement and returns an array with each sub-statement.
# Example:
#    INSERT INTO ... SELECT ...
# is split into two statements: "INSERT INTO ..." and "SELECT ...".
sub split {
   my ( $self, $query ) = @_;
   return unless $query;
   $query = $self->clean_query($query);
   PTDEBUG && _d('Splitting', $query);

   my $verbs = qr{SELECT|INSERT|UPDATE|DELETE|REPLACE|UNION|CREATE}i;

   # This splits a statement on the above verbs which means that the verb
   # gets chopped out.  Capturing the verb (e.g. ($verb)) will retain it,
   # but then it's disjointed from its statement.  Example: for this query,
   #   INSERT INTO ... SELECT ...
   # split returns ('INSERT', 'INTO ...', 'SELECT', '...').  Therefore,
   # we must re-attach each verb to its statement; we do this later...
   my @split_statements = grep { $_ } split(m/\b($verbs\b(?!(?:\s*\()))/io, $query);

   my @statements;
   if ( @split_statements == 1 ) {
      # This happens if the query has no verbs, so it's probably a single
      # statement.
      push @statements, $query;
   }
   else {
      # ...Re-attach verbs to their statements.
      for ( my $i = 0; $i <= $#split_statements; $i += 2 ) {
         push @statements, $split_statements[$i].$split_statements[$i+1];

         # Variable-width negative look-behind assertions, (?<!), aren't
         # fully supported so we split ON DUPLICATE KEY UPDATE.  This
         # puts it back together.
         if ( $statements[-2] && $statements[-2] =~ m/on duplicate key\s+$/i ) {
            $statements[-2] .= pop @statements;
         }
      }
   }

   # Wrap stmts in <> to make it more clear where each one begins/ends.
   PTDEBUG && _d('statements:', map { $_ ? "<$_>" : 'none' } @statements);
   return @statements;
}

sub clean_query {
   my ( $self, $query ) = @_;
   return unless $query;
   $query =~ s!/\*.*?\*/! !g;  # Remove /* comment blocks */
   $query =~ s/^\s+//;         # Remove leading spaces
   $query =~ s/\s+$//;         # Remove trailing spaces
   $query =~ s/\s{2,}/ /g;     # Remove extra spaces
   return $query;
}

sub split_subquery {
   my ( $self, $query ) = @_;
   return unless $query;
   $query = $self->clean_query($query);
   $query =~ s/;$//;

   my @subqueries;
   my $sqno = 0;  # subquery number
   my $pos  = 0;
   while ( $query =~ m/(\S+)(?:\s+|\Z)/g ) {
      $pos = pos($query);
      my $word = $1;
      PTDEBUG && _d($word, $sqno);
      if ( $word =~ m/^\(?SELECT\b/i ) {
         my $start_pos = $pos - length($word) - 1;
         if ( $start_pos ) {
            $sqno++;
            PTDEBUG && _d('Subquery', $sqno, 'starts at', $start_pos);
            $subqueries[$sqno] = {
               start_pos => $start_pos,
               end_pos   => 0,
               len       => 0,
               words     => [$word],
               lp        => 1, # left parentheses
               rp        => 0, # right parentheses
               done      => 0,
            };
         }
         else {
            PTDEBUG && _d('Main SELECT at pos 0');
         }
      }
      else {
         next unless $sqno;  # next unless we're in a subquery
         PTDEBUG && _d('In subquery', $sqno);
         my $sq = $subqueries[$sqno];
         if ( $sq->{done} ) {
            PTDEBUG && _d('This subquery is done; SQL is for',
               ($sqno - 1 ? "subquery $sqno" : "the main SELECT"));
            next;
         }
         push @{$sq->{words}}, $word;
         my $lp = ($word =~ tr/\(//) || 0;
         my $rp = ($word =~ tr/\)//) || 0;
         PTDEBUG && _d('parentheses left', $lp, 'right', $rp);
         if ( ($sq->{lp} + $lp) - ($sq->{rp} + $rp) == 0 ) {
            my $end_pos = $pos - 1;
            PTDEBUG && _d('Subquery', $sqno, 'ends at', $end_pos);
            $sq->{end_pos} = $end_pos;
            $sq->{len}     = $end_pos - $sq->{start_pos};
         }
      }
   }

   for my $i ( 1..$#subqueries ) {
      my $sq = $subqueries[$i];
      next unless $sq;
      $sq->{sql} = join(' ', @{$sq->{words}});
      substr $query,
         $sq->{start_pos} + 1,  # +1 for (
         $sq->{len} - 1,        # -1 for )
         "__subquery_$i";
   }

   return $query, map { $_->{sql} } grep { defined $_ } @subqueries;
}

sub query_type {
   my ( $self, $query, $qr ) = @_;
   my ($type, undef) = $qr->distill_verbs($query);
   my $rw;
   if ( $type =~ m/^SELECT\b/ ) {
      $rw = 'read';
   }
   elsif ( $type =~ m/^$data_manip_stmts\b/
           || $type =~ m/^$data_def_stmts\b/  ) {
      $rw = 'write'
   }

   return {
      type => $type,
      rw   => $rw,
   }
}

sub get_columns {
   my ( $self, $query ) = @_;
   my $cols = [];
   return $cols unless $query;
   my $cols_def;

   if ( $query =~ m/^SELECT/i ) {
      $query =~ s/
         ^SELECT\s+
           (?:ALL
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
           )\s+
      /SELECT /xgi;
      ($cols_def) = $query =~ m/^SELECT\s+(.+?)\s+FROM/i;
   }
   elsif ( $query =~ m/^(?:INSERT|REPLACE)/i ) {
      ($cols_def) = $query =~ m/\(([^\)]+)\)\s*VALUE/i;
   }

   PTDEBUG && _d('Columns:', $cols_def);
   if ( $cols_def ) {
      @$cols = split(',', $cols_def);
      map {
         my $col = $_;
         $col = s/^\s+//g;
         $col = s/\s+$//g;
         $col;
      } @$cols;
   }

   return $cols;
}

sub parse {
   my ( $self, $query ) = @_;
   return unless $query;
   my $parsed = {};

   # Flatten and clean query.
   $query =~ s/\n/ /g;
   $query = $self->clean_query($query);

   $parsed->{query}   = $query,
   $parsed->{tables}  = $self->get_aliases($query, 1);
   $parsed->{columns} = $self->get_columns($query);

   my ($type) = $query =~ m/^(\w+)/;
   $parsed->{type} = lc $type;

   # my @words = $query =~ m/
   #   [A-Za-z_.]+\(.*?\)+   # Match FUNCTION(...)
   #   |\(.*?\)+             # Match grouped items
   #   |"(?:[^"]|\"|"")*"+   # Match double quotes
   #   |'[^'](?:|\'|'')*'+   #   and single quotes
   #   |`(?:[^`]|``)*`+      #   and backticks
   #   |[^ ,]+
   #   |,
   #/gx;

   $parsed->{sub_queries} = [];

   return $parsed;
}

# Returns an array of arrayrefs like [db,tbl] for each unique db.tbl
# in the query and its subqueries.  db may be undef.
sub extract_tables {
   my ( $self, %args ) = @_;
   my $query      = $args{query};
   my $default_db = $args{default_db};
   my $q          = $self->{Quoter} || $args{Quoter};
   return unless $query;
   PTDEBUG && _d('Extracting tables');
   my @tables;
   my %seen;
   foreach my $db_tbl ( $self->get_tables($query) ) {
      next unless $db_tbl;
      next if $seen{$db_tbl}++; # Unique-ify for issue 337.
      my ( $db, $tbl ) = $q->split_unquote($db_tbl);
      push @tables, [ $db || $default_db, $tbl ];
   }
   return @tables;
}

# This is a special trim function that removes whitespace and identifier-quotes
# (backticks, in the case of MySQL) from the string.
sub trim_identifier {
   my ($self, $str) = @_;
   return unless defined $str;
   $str =~ s/`//g;
   $str =~ s/^\s+//;
   $str =~ s/\s+$//;
   return $str;
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
# End QueryParser package
# ###########################################################################
