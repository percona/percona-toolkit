#!/usr/bin/perl

# ##########################################################################
# This is a magic test file that is designed to be run manually.
# ##########################################################################

# This program is copyright (c) 2007 Baron Schwartz.
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
use strict;
use warnings FATAL => 'all';

use Test::More qw(no_plan);
use English qw(-no_match_vars);
use DBI;

require "../TableParser.pm";
require "../MySQLFind.pm";
require "../MySQLDump.pm";
require "../Quoter.pm";

my $p = new TableParser();
my $q = new Quoter();
my $d = new MySQLDump();
my $t;

# This part of the test inspects every table in the local MySQL server, if a
# connection can be made.  It checks that parsing produces the same columns
# and types and nullability etc as reported by SHOW COLUMNS.

my $dbh;
eval {
   $dbh = DBI->connect(
   "DBI:mysql:;mysql_read_default_group=mysql", undef, undef,
   { PrintError => 0, RaiseError => 1 })
};
if ( $EVAL_ERROR ) {
   diag "Cannot connect";
   exit(0);
}

my $f = new MySQLFind(
   dbh    => $dbh,
   quoter => $q,
   engines => {
      views => 0,
   },
);

foreach my $database ( $f->find_databases() ) {
   foreach my $table ( $f->find_tables(database => $database) ) {
      my $ddl  = $d->get_create_table($dbh, $q, $database, $table);
      my $str  = $p->parse($ddl);
      my $cols = $d->get_columns($dbh, $q, $database, $table);

      is_deeply(
         $str->{cols},
         [ map { $_->{field} } @$cols ],
         "Columns for $database.$table",
      );

      is_deeply(
         $str->{type_for},
         { map {
            my $t = $_->{type};
            $t =~ s/\W.*$//;
            $_->{field} => $t;
         } @$cols },
         "Column types for $database.$table",
      );

      is_deeply(
         $str->{null_cols},
         [ map { $_->{field} } grep { $_->{null} eq 'YES' } @$cols ],
         "Nullability for $database.$table",
      );

   }
}
