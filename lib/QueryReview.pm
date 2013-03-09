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
# QueryReview package
# ###########################################################################
{
# Package: QueryReview
# QueryReview is an API to a query review table.
# This module is an interface to a "query review table" in which certain
# historical information about classes of queries is stored.  See the docs on
# mk-query-digest for context.
package QueryReview;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

Transformers->import(qw(make_checksum parse_timestamp));

# These columns are the minimal set of columns for every review table.  TODO:
# maybe it's possible to specify this in the tool's POD and pass it in so it's
# not hardcoded here and liable to get out of sync.
my %basic_cols = map { $_ => 1 }
   qw(checksum fingerprint sample first_seen last_seen reviewed_by
      reviewed_on comments);
my %skip_cols  = map { $_ => 1 } qw(fingerprint sample checksum);

# Required args:
# dbh           A dbh to the server with the query review table.
# db_tbl        Full quoted db.tbl name of the query review table.
#               Make sure the table exists! It's not checked here;
#               check it before instantiating an object.
# tbl_struct    Return val from TableParser::parse() for db_tbl.
#               This is used to discover what columns db_tbl has.
# quoter        Quoter object.
#
# Optional args:
# ts_default    SQL expression to use when inserting a new row into
#               the review table.  If nothing else is specified, NOW()
#               is the default.  This is for dependency injection while
#               testing.
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(dbh db_tbl tbl_struct quoter) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   foreach my $col ( keys %basic_cols ) {
      die "Query review table $args{db_tbl} does not have a $col column"
         unless $args{tbl_struct}->{is_col}->{$col};
   }

   my $now = defined $args{ts_default} ? $args{ts_default} : 'NOW()';

   # Design statements to INSERT and statements to SELECT from the review table.
   my $sql = <<"      SQL";
      INSERT INTO $args{db_tbl}
      (checksum, fingerprint, sample, first_seen, last_seen)
      VALUES(CONV(?, 16, 10), ?, ?, COALESCE(?, $now), COALESCE(?, $now))
      ON DUPLICATE KEY UPDATE
         first_seen = IF(
            first_seen IS NULL,
            COALESCE(?, $now),
            LEAST(first_seen, COALESCE(?, $now))),
         last_seen = IF(
            last_seen IS NULL,
            COALESCE(?, $now),
            GREATEST(last_seen, COALESCE(?, $now)))
      SQL
   PTDEBUG && _d('SQL to insert into review table:', $sql);
   my $insert_sth = $args{dbh}->prepare($sql);

   # The SELECT statement does not need to get the fingerprint, sample or
   # checksum.
   my @review_cols = grep { !$skip_cols{$_} } @{$args{tbl_struct}->{cols}};
   $sql = "SELECT "
        . join(', ', map { $args{quoter}->quote($_) } @review_cols)
        . ", CONV(checksum, 10, 16) AS checksum_conv FROM $args{db_tbl}"
        . " WHERE checksum=CONV(?, 16, 10)";
   PTDEBUG && _d('SQL to select from review table:', $sql);
   my $select_sth = $args{dbh}->prepare($sql);

   my $self = {
      dbh         => $args{dbh},
      db_tbl      => $args{db_tbl},
      insert_sth  => $insert_sth,
      select_sth  => $select_sth,
      tbl_struct  => $args{tbl_struct},
      quoter      => $args{quoter},
      ts_default  => $now,
   };
   return bless $self, $class;
}

# Fetch information from the database about a query that's been reviewed.
sub get_review_info {
   my ( $self, $id ) = @_;
   $self->{select_sth}->execute(make_checksum($id));
   my $review_vals = $self->{select_sth}->fetchall_arrayref({});
   if ( $review_vals && @$review_vals == 1 ) {
      return $review_vals->[0];
   }
   return undef;
}

# Store a query into the table.  The arguments are:
#  *  fingerprint
#  *  sample
#  *  first_seen
#  *  last_seen
# There's no need to convert the fingerprint to a checksum, no need to parse
# timestamps either.
sub set_review_info {
   my ( $self, %args ) = @_;
   $self->{insert_sth}->execute(
      make_checksum($args{fingerprint}),
      @args{qw(fingerprint sample)},
      map { $args{$_} ? parse_timestamp($args{$_}) : undef }
         qw(first_seen last_seen first_seen first_seen last_seen last_seen));
}

# Return the columns we'll be using from the review table.
sub review_cols {
   my ( $self ) = @_;
   return grep { !$skip_cols{$_} } @{$self->{tbl_struct}->{cols}};
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
# End QueryReview package
# ###########################################################################
