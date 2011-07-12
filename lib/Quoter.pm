# This program is copyright 2007-2011 Baron Schwartz, 2011 Percona Inc.
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
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

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
   my ( $self, $val ) = @_;

   return 'NULL' unless defined $val;          # undef = NULL
   return "''" if $val eq '';                  # blank string = ''
   return $val if $val =~ m/^0x[0-9a-fA-F]+$/;  # hex data

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
   $db_tbl =~ s/`//g;
   my ( $db, $tbl ) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
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

1;
}
# ###########################################################################
# End Quoter package
# ###########################################################################
