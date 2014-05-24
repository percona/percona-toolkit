# This program is copyright 2007-2011 Baron Schwartz, 2011 Percona Ireland Ltd.
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
# QueryRewriter package
# ###########################################################################
{
# Package: QueryRewriter
# QueryRewriter rewrites and transforms queries.
package QueryRewriter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# A list of verbs that can appear in queries.  I know this is incomplete -- it
# does not have CREATE, DROP, ALTER, TRUNCATE for example.  But I don't need
# those for my client yet.  Other verbs: KILL, LOCK, UNLOCK
our $verbs   = qr{^SHOW|^FLUSH|^COMMIT|^ROLLBACK|^BEGIN|SELECT|INSERT
                  |UPDATE|DELETE|REPLACE|^SET|UNION|^START|^LOCK}xi;
my $quote_re = qr/"(?:(?!(?<!\\)").)*"|'(?:(?!(?<!\\)').)*'/; # Costly!
my $bal;
$bal         = qr/
                  \(
                  (?:
                     (?> [^()]+ )    # Non-parens without backtracking
                     |
                     (??{ $bal })    # Group with matching parens
                  )*
                  \)
                 /x;

# The one-line comment pattern is quite crude.  This is intentional for
# performance.  The multi-line pattern does not match version-comments.
my $olc_re = qr/(?:--|#)[^'"\r\n]*(?=[\r\n]|\Z)/;  # One-line comments
my $mlc_re = qr#/\*[^!].*?\*/#sm;                  # But not /*!version */
my $vlc_re = qr#/\*.*?[0-9]+.*?\*/#sm;             # For SHOW + /*!version */
my $vlc_rf = qr#^(?:SHOW).*?/\*![0-9]+(.*?)\*/#sm;     # Variation for SHOW


sub new {
   my ( $class, %args ) = @_;
   my $self = { %args };
   return bless $self, $class;
}

# Strips comments out of queries.
sub strip_comments {
   my ( $self, $query ) = @_;
   return unless $query;
   $query =~ s/$mlc_re//go;
   $query =~ s/$olc_re//go;
   if ( $query =~ m/$vlc_rf/i ) { # contains show + version
      my $qualifier = $1 || '';
      $query =~ s/$vlc_re/$qualifier/go;
   }
   return $query;
}

# Shortens long queries by normalizing stuff out of them.  $length is used only
# for IN() lists.  If $length is given, the query is shortened if it's longer
# than that.
sub shorten {
   my ( $self, $query, $length ) = @_;
   # Shorten multi-value insert/replace, all the way up to on duplicate key
   # update if it exists.
   $query =~ s{
      \A(
         (?:INSERT|REPLACE)
         (?:\s+LOW_PRIORITY|DELAYED|HIGH_PRIORITY|IGNORE)?
         (?:\s\w+)*\s+\S+\s+VALUES\s*\(.*?\)
      )
      \s*,\s*\(.*?(ON\s+DUPLICATE|\Z)}
      {$1 /*... omitted ...*/$2}xsi;

   # Shortcut!  Find out if there's an IN() list with values.
   return $query unless $query =~ m/IN\s*\(\s*(?!select)/i;

   # Shorten long IN() lists of literals.  But only if the string is longer than
   # the $length limit.  Assumption: values don't contain commas or closing
   # parens inside them.
   my $last_length  = 0;
   my $query_length = length($query);
   while (
      $length          > 0
      && $query_length > $length
      && $query_length < ( $last_length || $query_length + 1 )
   ) {
      $last_length = $query_length;
      $query =~ s{
         (\bIN\s*\()    # The opening of an IN list
         ([^\)]+)       # Contents of the list, assuming no item contains paren
         (?=\))           # Close of the list
      }
      {
         $1 . __shorten($2)
      }gexsi;
   }

   return $query;
}

# Used by shorten().  The argument is the stuff inside an IN() list.  The
# argument might look like this:
#  1,2,3,4,5,6
# Or, if this is a second or greater iteration, it could even look like this:
#  /*... omitted 5 items ...*/ 6,7,8,9
# In the second case, we need to trim out 6,7,8 and increment "5 items" to "8
# items".  We assume that the values in the list don't contain commas; if they
# do, the results could be a little bit wrong, but who cares.  We keep the first
# 20 items because we don't want to nuke all the samples from the query, we just
# want to shorten it.
sub __shorten {
   my ( $snippet ) = @_;
   my @vals = split(/,/, $snippet);
   return $snippet unless @vals > 20;
   my @keep = splice(@vals, 0, 20);  # Remove and save the first 20 items
   return
      join(',', @keep)
      . "/*... omitted "
      . scalar(@vals)
      . " items ...*/";
}

# Normalizes variable queries to a "query fingerprint" by abstracting away
# parameters, canonicalizing whitespace, etc.  See
# http://dev.mysql.com/doc/refman/5.0/en/literals.html for literal syntax.
# Note: Any changes to this function must be profiled for speed!  Speed of this
# function is critical for pt-query-digest.  There are known bugs in this,
# but the balance between maybe-you-get-a-bug and speed favors speed.
# See past Maatkit revisions of this subroutine for more correct, but slower,
# regexes.
sub fingerprint {
   my ( $self, $query ) = @_;

   # First, we start with a bunch of special cases that we can optimize because
   # they are special behavior or because they are really big and we want to
   # throw them away as early as possible.
   $query =~ m#\ASELECT /\*!40001 SQL_NO_CACHE \*/ \* FROM `# # mysqldump query
      && return 'mysqldump';
   # Matches queries like REPLACE /*foo.bar:3/3*/ INTO checksum.checksum
   $query =~ m#/\*\w+\.\w+:[0-9]/[0-9]\*/#     # pt-table-checksum, etc query
      && return 'percona-toolkit';
   # Administrator commands appear to be a comment, so return them as-is
   $query =~ m/\Aadministrator command: /
      && return $query;
   # Special-case for stored procedures.
   $query =~ m/\A\s*(call\s+\S+)\(/i
      && return lc($1); # Warning! $1 used, be careful.
   # mysqldump's INSERT statements will have long values() lists, don't waste
   # time on them... they also tend to segfault Perl on some machines when you
   # get to the "# Collapse IN() and VALUES() lists" regex below!
   if ( my ($beginning) = $query =~ m/\A((?:INSERT|REPLACE)(?: IGNORE)?\s+INTO.+?VALUES\s*\(.*?\))\s*,\s*\(/is ) {
      $query = $beginning; # Shorten multi-value INSERT statements ASAP
   }

   $query =~ s/$mlc_re//go;
   $query =~ s/$olc_re//go;
   $query =~ s/\Ause \S+\Z/use ?/i       # Abstract the DB in USE
      && return $query;

   $query =~ s/\\["']//g;                # quoted strings
   $query =~ s/".*?"/?/sg;               # quoted strings
   $query =~ s/'.*?'/?/sg;               # quoted strings

   $query =~ s/\bfalse\b|\btrue\b/?/isg; # boolean values 

   # MD5 checksums which are always 32 hex chars 
   if ( $self->{match_md5_checksums} ) { 
      $query =~ s/([._-])[a-f0-9]{32}/$1?/g;
   }

   # Things resembling numbers/hex.
   if ( !$self->{match_embedded_numbers} ) {
      # For speed, this regex is extremely broad in its definition
      # of what looks like a number.
      $query =~ s/[0-9+-][0-9a-f.xb+-]*/?/g;
   }
   else {
      $query =~ s/\b[0-9+-][0-9a-f.xb+-]*/?/g;
   }

   # Clean up leftovers
   if ( $self->{match_md5_checksums} ) {
      $query =~ s/[xb+-]\?/?/g;                
   }
   else {
      $query =~ s/[xb.+-]\?/?/g;
   }

   $query =~ s/\A\s+//;                  # Chop off leading whitespace
   chomp $query;                         # Kill trailing whitespace
   $query =~ tr[ \n\t\r\f][ ]s;          # Collapse whitespace
   $query = lc $query;
   $query =~ s/\bnull\b/?/g;             # Get rid of NULLs
   $query =~ s{                          # Collapse IN and VALUES lists
               \b(in|values?)(?:[\s,]*\([\s?,]*\))+
              }
              {$1(?+)}gx;
   $query =~ s{                          # Collapse UNION
               \b(select\s.*?)(?:(\sunion(?:\sall)?)\s\1)+
              }
              {$1 /*repeat$2*/}xg;
   $query =~ s/\blimit \?(?:, ?\?| offset \?)?/limit ?/; # LIMIT
   # The following are disabled because of speed issues.  Should we try to
   # normalize whitespace between and around operators?  My gut feeling is no.
   # $query =~ s/ , | ,|, /,/g;    # Normalize commas
   # $query =~ s/ = | =|= /=/g;       # Normalize equals
   # $query =~ s# [,=+*/-] ?|[,=+*/-] #+#g;    # Normalize operators

   # Remove ASC keywords from ORDER BY clause so these queries fingerprint
   # the same:
   #   SELECT * FROM `products`  ORDER BY name ASC, shape ASC;
   #   SELECT * FROM `products`  ORDER BY name, shape;
   # ASC is default so "ORDER BY col ASC" is really the same as just
   # "ORDER BY col".
   # http://code.google.com/p/maatkit/issues/detail?id=1030
   if ( $query =~ m/\bORDER BY /gi ) {  # Find, anchor on ORDER BY clause
      # Replace any occurrence of "ASC" after anchor until end of query.
      # I have verified this with regex debug: it's a single forward pass
      # without backtracking.  Probably as fast as it gets.
      1 while $query =~ s/\G(.+?)\s+ASC/$1/gi && pos $query;
   }

   return $query;
}

# Gets the verbs from an SQL query, such as SELECT, UPDATE, etc.
sub distill_verbs {
   my ( $self, $query ) = @_;

   # Simple verbs that normally don't have comments, extra clauses, etc.
   $query =~ m/\A\s*call\s+(\S+)\(/i && return "CALL $1";
   $query =~ m/\A\s*use\s+/          && return "USE";
   $query =~ m/\A\s*UNLOCK TABLES/i  && return "UNLOCK";
   $query =~ m/\A\s*xa\s+(\S+)/i     && return "XA_$1";

   if ( $query =~ m/\A\s*LOAD/i ) {
      my ($tbl) = $query =~ m/INTO TABLE\s+(\S+)/i;
      $tbl ||= '';
      $tbl =~ s/`//g;
      return "LOAD DATA $tbl";
   }

   if ( $query =~ m/\Aadministrator command:/ ) {
      $query =~ s/administrator command:/ADMIN/;
      $query = uc $query;
      return $query;
   }

   # All other, more complex verbs. 
   $query = $self->strip_comments($query);

   # SHOW statements are either 2 or 3 words: SHOW A (B), where A and B
   # are words; B is optional.  E.g. "SHOW TABLES" or "SHOW SLAVE STATUS". 
   # There's a few common keywords that may show up in place of A, so we
   # remove them first.  Then there's some keywords that signify extra clauses
   # that may show up in place of B and since these clauses are at the
   # end of the statement, we remove everything from the clause onward.
   if ( $query =~ m/\A\s*SHOW\s+/i ) {
      PTDEBUG && _d($query);

      # Remove common keywords.
      $query = uc $query;
      $query =~ s/\s+(?:SESSION|FULL|STORAGE|ENGINE)\b/ /g;
      # This should be in the regex above but Perl doesn't seem to match
      # COUNT\(.+\) properly when it's grouped.
      $query =~ s/\s+COUNT[^)]+\)//g;

      # Remove clause keywords and everything after.
      $query =~ s/\s+(?:FOR|FROM|LIKE|WHERE|LIMIT|IN)\b.+//ms;

      # The query should now be like SHOW A B C ... delete everything after B,
      # collapse whitespace, and we're done.
      $query =~ s/\A(SHOW(?:\s+\S+){1,2}).*\Z/$1/s;
      $query =~ s/\s+/ /g;
      PTDEBUG && _d($query);
      return $query;
   }

   # Data defintion statements verbs like CREATE and ALTER.
   # The two evals are a hack to keep Perl from warning that
   # "QueryParser::data_def_stmts" used only once: possible typo at...".
   # Some day we'll group all our common regex together in a packet and
   # export/import them properly.
   eval $QueryParser::data_def_stmts;
   eval $QueryParser::tbl_ident;
   my ( $dds ) = $query =~ /^\s*($QueryParser::data_def_stmts)\b/i;
   if ( $dds) {
      # https://bugs.launchpad.net/percona-toolkit/+bug/821690
      $query =~ s/\s+IF(?:\s+NOT)?\s+EXISTS/ /i;
      my ( $obj ) = $query =~ m/$dds.+(DATABASE|TABLE)\b/i;
      $obj = uc $obj if $obj;
      PTDEBUG && _d('Data def statment:', $dds, 'obj:', $obj);
      my ($db_or_tbl)
         = $query =~ m/(?:TABLE|DATABASE)\s+($QueryParser::tbl_ident)(\s+.*)?/i;
      PTDEBUG && _d('Matches db or table:', $db_or_tbl);
      return uc($dds . ($obj ? " $obj" : '')), $db_or_tbl;
   }

   # All other verbs, like SELECT, INSERT, UPDATE, etc.  First, get
   # the query type -- just extract all the verbs and collapse them
   # together.
   my @verbs = $query =~ m/\b($verbs)\b/gio;
   @verbs    = do {
      my $last = '';
      grep { my $pass = $_ ne $last; $last = $_; $pass } map { uc } @verbs;
   };

   # http://code.google.com/p/maatkit/issues/detail?id=1176
   # A SELECT query can't have any verbs other than UNION.
   # Subqueries (SELECT SELECT) are reduced to 1 SELECT in the
   # do loop above.  And there's no valid SQL syntax like
   # SELECT ... DELETE (there are valid multi-verb syntaxes, like
   # INSERT ... SELECT).  So if it's a SELECT with multiple verbs,
   # we need to check it else SELECT c FROM t WHERE col='delete'
   # will incorrectly distill as SELECT DELETE t.
   if ( ($verbs[0] || '') eq 'SELECT' && @verbs > 1 ) {
      PTDEBUG && _d("False-positive verbs after SELECT:", @verbs[1..$#verbs]);
      my $union = grep { $_ eq 'UNION' } @verbs;
      @verbs    = $union ? qw(SELECT UNION) : qw(SELECT);
   }

   # This used to be "my $verbs" but older verisons of Perl complain that
   # ""my" variable $verbs masks earlier declaration in same scope" where
   # the earlier declaration is our $verbs.
   # http://code.google.com/p/maatkit/issues/detail?id=957
   my $verb_str = join(q{ }, @verbs);
   return $verb_str;
}

sub __distill_tables {
   my ( $self, $query, $table, %args ) = @_;
   my $qp = $args{QueryParser} || $self->{QueryParser};
   die "I need a QueryParser argument" unless $qp;

   # "Fingerprint" the tables.
   my @tables = map {
      $_ =~ s/`//g;
      $_ =~ s/(_?)[0-9]+/$1?/g;
      $_;
   } grep { defined $_ } $qp->get_tables($query);

   push @tables, $table if $table;

   # Collapse the table list
   @tables = do {
      my $last = '';
      grep { my $pass = $_ ne $last; $last = $_; $pass } @tables;
   };

   return @tables;
}

# This is kind of like fingerprinting, but it super-fingerprints to something
# that shows the query type and the tables/objects it accesses.
sub distill {
   my ( $self, $query, %args ) = @_;

   if ( $args{generic} ) {
      # Do a generic distillation which returns the first two words
      # of a simple "cmd arg" query, like memcached and HTTP stuff.
      my ($cmd, $arg) = $query =~ m/^(\S+)\s+(\S+)/;
      return '' unless $cmd;
      $query = (uc $cmd) . ($arg ? " $arg" : '');
   }
   else {
      # distill_verbs() may return a table if it's a special statement
      # like TRUNCATE TABLE foo.  __distill_tables() handles some but not
      # all special statements so we pass the special table from distill_verbs()
      # to __distill_tables() in case it's a statement that the latter
      # can't handle.  If it can handle it, it will eliminate any duplicate
      # tables.
      my ($verbs, $table)  = $self->distill_verbs($query, %args);

      if ( $verbs && $verbs =~ m/^SHOW/ ) {
         # Ignore tables for SHOW statements and normalize some
         # aliases like SCHMEA==DATABASE, KEYS==INDEX.
         my %alias_for = qw(
            SCHEMA   DATABASE
            KEYS     INDEX
            INDEXES  INDEX
         );
         map { $verbs =~ s/$_/$alias_for{$_}/ } keys %alias_for;
         $query = $verbs;
      }
      elsif ( $verbs && $verbs =~ m/^LOAD DATA/ ) {
         return $verbs;
      }
      else {
         # For everything else, distill the tables.
         my @tables = $self->__distill_tables($query, $table, %args);
         $query     = join(q{ }, $verbs, @tables); 
      } 
   }

   if ( $args{trf} ) {
      $query = $args{trf}->($query, %args);
   }

   return $query;
}

sub convert_to_select {
   my ( $self, $query ) = @_;
   return unless $query;

   # Trying to convert statments that have subqueries as values to column
   # assignments doesn't work.  E.g. SET col=(SELECT ...).  But subqueries
   # do work in other cases like JOIN (SELECT ...).
   # http://code.google.com/p/maatkit/issues/detail?id=347
   return if $query =~ m/=\s*\(\s*SELECT /i;

   $query =~ s{
                 \A.*?
                 update(?:\s+(?:low_priority|ignore))?\s+(.*?)
                 \s+set\b(.*?)
                 (?:\s*where\b(.*?))?
                 (limit\s*[0-9]+(?:\s*,\s*[0-9]+)?)?
                 \Z
              }
              {__update_to_select($1, $2, $3, $4)}exsi
      # INSERT|REPLACE tbl (cols) VALUES (vals)
      || $query =~ s{
                    \A.*?
                    (?:insert(?:\s+ignore)?|replace)\s+
                    .*?\binto\b(.*?)\(([^\)]+)\)\s*
                    values?\s*(\(.*?\))\s*
                    (?:\blimit\b|on\s+duplicate\s+key.*)?\s*
                    \Z
                 }
                 {__insert_to_select($1, $2, $3)}exsi
      # INSERT|REPLACE tbl SET vals
      || $query =~ s{
                    \A.*?
                    (?:insert(?:\s+ignore)?|replace)\s+
                    (?:.*?\binto)\b(.*?)\s*
                    set\s+(.*?)\s*
                    (?:\blimit\b|on\s+duplicate\s+key.*)?\s*
                    \Z
                 }
                 {__insert_to_select_with_set($1, $2)}exsi
      || $query =~ s{
                    \A.*?
                    delete\s+(.*?)
                    \bfrom\b(.*)
                    \Z
                 }
                 {__delete_to_select($1, $2)}exsi;
   $query =~ s/\s*on\s+duplicate\s+key\s+update.*\Z//si;
   $query =~ s/\A.*?(?=\bSELECT\s*\b)//ism;
   return $query;
}

sub convert_select_list {
   my ( $self, $query ) = @_;
   $query =~ s{
               \A\s*select(.*?)\bfrom\b
              }
              {$1 =~ m/\*/ ? "select 1 from" : "select isnull(coalesce($1)) from"}exi;
   return $query;
}

sub __delete_to_select {
   my ( $delete, $join ) = @_;
   if ( $join =~ m/\bjoin\b/ ) {
      return "select 1 from $join";
   }
   return "select * from $join";
}

sub __insert_to_select {
   my ( $tbl, $cols, $vals ) = @_;
   PTDEBUG && _d('Args:', @_);
   my @cols = split(/,/, $cols);
   PTDEBUG && _d('Cols:', @cols);
   $vals =~ s/^\(|\)$//g; # Strip leading/trailing parens
   my @vals = $vals =~ m/($quote_re|[^,]*${bal}[^,]*|[^,]+)/g;
   PTDEBUG && _d('Vals:', @vals);
   if ( @cols == @vals ) {
      return "select * from $tbl where "
         . join(' and ', map { "$cols[$_]=$vals[$_]" } (0..$#cols));
   }
   else {
      return "select * from $tbl limit 1";
   }
}

sub __insert_to_select_with_set {
   my ( $from, $set ) = @_;
   $set =~ s/,/ and /g;
   return "select * from $from where $set ";
}

sub __update_to_select {
   my ( $from, $set, $where, $limit ) = @_;
   return "select $set from $from "
      . ( $where ? "where $where" : '' )
      . ( $limit ? " $limit "      : '' );
}

sub wrap_in_derived {
   my ( $self, $query ) = @_;
   return unless $query;
   return $query =~ m/\A\s*select/i
      ? "select 1 from ($query) as x limit 1"
      : $query;
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
# End QueryRewriter package
# ###########################################################################
