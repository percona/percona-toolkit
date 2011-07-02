# This program is copyright 2008-2011 Percona Inc.
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
# QueryReview package $Revision: 7342 $
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
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

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
   MKDEBUG && _d('SQL to insert into review table:', $sql);
   my $insert_sth = $args{dbh}->prepare($sql);

   # The SELECT statement does not need to get the fingerprint, sample or
   # checksum.
   my @review_cols = grep { !$skip_cols{$_} } @{$args{tbl_struct}->{cols}};
   $sql = "SELECT "
        . join(', ', map { $args{quoter}->quote($_) } @review_cols)
        . ", CONV(checksum, 10, 16) AS checksum_conv FROM $args{db_tbl}"
        . " WHERE checksum=CONV(?, 16, 10)";
   MKDEBUG && _d('SQL to select from review table:', $sql);
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

# Tell QueryReview object to also prepare to save values in the review history
# table.
sub set_history_options {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(table dbh tbl_struct col_pat) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   # Pick out columns, attributes and metrics that need to be stored in the
   # table.
   my @cols;
   my @metrics;
   foreach my $col ( @{$args{tbl_struct}->{cols}} ) {
      my ( $attr, $metric ) = $col =~ m/$args{col_pat}/;
      next unless $attr && $metric;

      # TableParser lowercases the column names so, e.g., Query_time
      # becomes query_time.  We have to fix this so attribs in the event
      # match keys in $self->{history_metrics}...

      # If the attrib name has at least one _ then it's a multi-word
      # attrib like Query_time or Lock_time, so the first letter should
      # be uppercase.  Else, it's a one-word attrib like ts, checksum
      # or sample, so we leave it alone.  Except Filesort which is yet
      # another exception.
      $attr = ucfirst $attr if $attr =~ m/_/;
      $attr = 'Filesort' if $attr eq 'filesort';

      $attr =~ s/^Qc_hit/QC_Hit/;  # Qc_hit is really QC_Hit
      $attr =~ s/^Innodb/InnoDB/g; # Innodb is really InnoDB
      $attr =~ s/_io_/_IO_/g;      # io is really IO

      push @cols, $col;
      push @metrics, [$attr, $metric];
   }

   my $sql = "REPLACE INTO $args{table}("
      . join(', ',
         map { $self->{quoter}->quote($_) } ('checksum', 'sample', @cols))
      . ') VALUES (CONV(?, 16, 10), ?'
      . (@cols ? ', ' : '')  # issue 1265
      . join(', ', map {
         # ts_min and ts_max might be part of the PK, in which case they must
         # not be NULL.
         $_ eq 'ts_min' || $_ eq 'ts_max'
            ? "COALESCE(?, $self->{ts_default})"
            : '?'
        } @cols) . ')';
   MKDEBUG && _d($sql);

   $self->{history_sth}     = $args{dbh}->prepare($sql);
   $self->{history_metrics} = \@metrics;

   return;
}

# Save review history for a class of queries.  The incoming data is a bunch
# of hashes.  Each top-level key is an attribute name, and each second-level key
# is a metric name.  Look at the test for more examples.
sub set_review_history {
   my ( $self, $id, $sample, %data ) = @_;
   # Need to transform ts->min/max into timestamps
   foreach my $thing ( qw(min max) ) {
      next unless defined $data{ts} && defined $data{ts}->{$thing};
      $data{ts}->{$thing} = parse_timestamp($data{ts}->{$thing});
   }
   $self->{history_sth}->execute(
      make_checksum($id),
      $sample,
      map { $data{$_->[0]}->{$_->[1]} } @{$self->{history_metrics}});
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
