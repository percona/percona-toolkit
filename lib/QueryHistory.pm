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
# QueryHistory package
# ###########################################################################
{
# Package: QueryHistory
package QueryHistory;

use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Lmo;

use Quoter;
use Transformers qw(make_checksum parse_timestamp);

has history_dbh => (
   is       => 'ro',
   required => 1,
);

has history_sth => (
   is => 'rw',
);

has history_metrics => (
   is => 'rw',
   isa => 'ArrayRef',
);

has column_pattern => (
   is       => 'ro',
   isa      => 'Regexp',
   required => 1,
);

has ts_default => (
   is      => 'ro',
   isa     => 'Str',
   default => sub { 'NOW()' },
);

# Tell QueryReview object to also prepare to save values in the review history
# table.
sub set_history_options {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(table tbl_struct) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $col_pat = $self->column_pattern();

   # Pick out columns, attributes and metrics that need to be stored in the
   # table.
   my @cols;
   my @metrics;
   foreach my $col ( @{$args{tbl_struct}->{cols}} ) {
      my ( $attr, $metric ) = $col =~ m/$col_pat/;
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

   my $ts_default = $self->ts_default;

   my $sql = "REPLACE INTO $args{table}("
      . join(', ',
         map { Quoter->quote($_) } ('checksum', 'sample', @cols))
      . ') VALUES (CONV(?, 16, 10), ?'
      . (@cols ? ', ' : '')  # issue 1265
      . join(', ', map {
         # ts_min and ts_max might be part of the PK, in which case they must
         # not be NULL.
         $_ eq 'ts_min' || $_ eq 'ts_max'
            ? "COALESCE(?, $ts_default)"
            : '?'
        } @cols) . ')';
   PTDEBUG && _d($sql);

   $self->history_sth($self->history_dbh->prepare($sql));
   $self->history_metrics(\@metrics);

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
   $self->history_sth->execute(
      make_checksum($id),
      $sample,
      map { $data{$_->[0]}->{$_->[1]} } @{$self->history_metrics});
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
# End QueryHistory package
# ###########################################################################
