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
# Quoter package
# ###########################################################################
{
# Package: Quoter
# Quoter handles value quoting, unquoting, escaping, etc.
package Quoter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Sub: new
#
# Parameters:
#   %args  - Arguments
#
# Returns:
#   Quoter object
sub new {
   my ( $class, %args ) = @_;
   return bless {}, $class;
}

# Sub: quote
#   Quote values in backticks.
#
# Parameters:
#   @vals - List of values to quote
#
# Returns:
#   Array of backtick-quoted values
sub quote {
   my ( $self, @vals ) = @_;
   foreach my $val ( @vals ) {
      $val =~ s/`/``/g;
   }
   return join('.', map { '`' . $_ . '`' } @vals);
}

# Sub: quote_val
#   Quote a value for use in a SQL statement.  Examples: undef = "NULL",
#   empty string = '', etc.
#
# Parameters:
#   $val - Value to quote
#
# Returns:
#   Quoted value
sub quote_val {
   my ( $self, $val, %args ) = @_;

   return 'NULL' unless defined $val;          # undef = NULL
   return "''" if $val eq '';                  # blank string = ''
   return $val if $val =~ m/^0x[0-9a-fA-F]+$/  # quote hex data
                  && !$args{is_char};          # unless is_char is true

   # Quote and return non-numeric vals.
   $val =~ s/(['\\])/\\$1/g;
   return "'$val'";
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
#
# See Also:
#   <join_quote>
sub split_unquote {
   my ( $self, $db_tbl, $default_db ) = @_;
   my ( $db, $tbl ) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   for ($db, $tbl) {
      next unless $_;
      s/\A`//;
      s/`\z//;
      s/``/`/g;
   }
   
   return ($db, $tbl);
}

# Sub: literal_like
#   Escape LIKE wildcard % and _.
#
# Parameters:
#   $like - LIKE value to escape
#
# Returns:
#   Escaped LIKE value
sub literal_like {
   my ( $self, $like ) = @_;
   return unless $like;
   $like =~ s/([%_])/\\$1/g;
   return "'$like'";
}

# Sub: join_quote
#   Join and backtick-quote a database name with a table name. This sub does
#   the opposite of split_unquote.
#
# Parameters:
#   $default_db - Default database name to use if $db_tbl is not
#                 database-qualified
#   $db_tbl     - Table name, optionally database-qualified, optionally
#                 quoted
#
# Returns:
#   Backtick-quoted, database-qualified table like `database`.`table`
#
# See Also:
#   <split_unquote>
sub join_quote {
   my ( $self, $default_db, $db_tbl ) = @_;
   return unless $db_tbl;
   my ($db, $tbl) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   $db  = "`$db`"  if $db  && $db  !~ m/^`/;
   $tbl = "`$tbl`" if $tbl && $tbl !~ m/^`/;
   return $db ? "$db.$tbl" : $tbl;
}

# Return the list passed in, with the elements passed through quotemeta,
# and the results concatenated with ','.
sub serialize_list {
   my ( $self, @args ) = @_;
   return unless @args;

   # If the only value is undef, which is NULL for MySQL, then return
   # the same.  undef/NULL is a valid boundary value, however...
   return $args[0] if @args == 1 && !defined $args[0];

   # ... if there's an undef/NULL value and more than one value,
   # then we have no easy way to serialize the values into a list.
   # We can't convert undef to "NULL" because "NULL" is a valid
   # value itself, and we can't make it "" because a blank string
   # is also a valid value.  In practice, a boundary value with
   # two NULL values should be rare.
   die "Cannot serialize multiple values with undef/NULL"
      if grep { !defined $_ } @args;

   return join ',', map { quotemeta } @args;
}

sub deserialize_list {
   my ( $self, $string ) = @_;
   return $string unless defined $string;
   my @escaped_parts = $string =~ /
         \G             # Start of string, or end of previous match.
         (              # Each of these is an element in the original list.
            [^\\,]*     # Anything not a backslash or a comma
            (?:         # When we get here, we found one of the above.
               \\.      # A backslash followed by something so we can continue
               [^\\,]*  # Same as above.
            )*          # Repeat zero of more times.
         )
         ,              # Comma dividing elements
      /sxgc;

   # Grab the rest of the string following the last match.
   # If there wasn't a last match, like for a single-element list,
   # the entire string represents the single element, so grab that.
   push @escaped_parts, pos($string) ? substr( $string, pos($string) ) : $string;

   # Undo the quotemeta().
   my @unescaped_parts = map {
      my $part = $_;
      # Here be weirdness. Unfortunately quotemeta() is broken, and exposes
      # the internal representation of scalars. Namely, the latin-1 range,
      # \128-\377 (\p{Latin1} in newer Perls) is all escaped in downgraded
      # strings, but left alone in UTF-8 strings. Thus, this.

      # TODO: quotemeta() might change in 5.16 to mean
      # qr/(?=\p{ASCII})\W|\p{Pattern_Syntax}/
      # And also fix this whole weird behavior under
      # use feature 'unicode_strings' --  If/once that's
      # implemented, this will have to change.
      my $char_class = utf8::is_utf8($part)  # If it's a UTF-8 string,
                     ? qr/(?=\p{ASCII})\W/   # We only care about non-word
                                             # characters in the ASCII range
                     : qr/(?=\p{ASCII})\W|[\x{80}-\x{FF}]/; # Otherwise,
                                             # same as above, but also
                                             # unescape the latin-1 range.
      $part =~ s/\\($char_class)/$1/g;
      $part;
   } @escaped_parts;

   return @unescaped_parts;
}

1;
}
# ###########################################################################
# End Quoter package
# ###########################################################################
