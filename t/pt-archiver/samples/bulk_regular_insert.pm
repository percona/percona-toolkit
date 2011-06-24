# This program is copyright 2010 Percona Inc.
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

# This package is an mk-archiver --dest plugin which implements a bulk
# INSERT using a regular INSERT statement rather than LOAD DATA that
# --bulk-insert normally uses.  This is accomplished by override two
# bulk operation calls.  The first, before_bulk_insert(),  reads the
# bulk insert file that mk-archiver wants to load and build one large
# INSERT statement from it.  The second, custom_sth_bulk(), returns a
# fake sth so that mk-archiver does not actually execute LOAD DATA.
# mk-archiver handles the bulk delete on the source.
package bulk_regular_insert;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG  => $ENV{MKDEBUG};

# ###########################################################################
# Customize these values for your tables.
# ###########################################################################

# There's nothing to customize yet.

# ###########################################################################
# Don't modify anything below here.
# ###########################################################################
sub new {
   my ( $class, %args ) = @_;
   my $o = $args{OptionParser};

   my $self = {
      %args,  # dbh, db, tbl, and some common modules
   };

   if ( $o->get('dry-run') ) {
      print "# bulk_regular_insert plugin\n";
   }

   return bless $self, $class;
}

sub before_begin {
   my ( $self, %args ) = @_;
   $self->{cols} = $args{allcols};
   return;
}

# This is a --dest plugin so we don't need to override is_archivable().
# sub is_archivable {
#   my ( $self, %args ) = @_;
#   return 1;
# }

# Reads rows from the LOAD DATA INFILE file, and instead of inserting them
# with LOAD DATA INFILE, builds a big conventional SQL INSERT... VALUES(),(),..
# Supports --replace and --ignore, just like the normal bulk insert.
sub before_bulk_insert {
   my ( $self, %args ) = @_;

   my $dbh    = $self->{dbh};
   my $q      = $self->{Quoter};
   my $o      = $self->{OptionParser};
   my $db_tbl = $q->quote($self->{db}, $self->{tbl});

   my $file = $args{filename};
   open my $fh, '<', $file 
      or die "Cannot open bulk insert file $file: $OS_ERROR";

   my $verb   = $o->get('replace') ? 'REPLACE' : 'INSERT';
   my $ignore = $o->get('ignore')  ? ' IGNORE' : '';
   my $sql = "$verb$ignore INTO $db_tbl ("
           . join(", ", map { $q->quote($_) } @{$self->{cols}})
           . ") VALUES ";

   my @vals;
   while ( my $line = <$fh> ) {
      chop $line;
      push @vals,
         "(" . join(", ", map { $q->quote_val($_) } split /\t/, $line) . ")";
   }
   $sql .= join(", ", @vals);
   $sql .= " /* mk-archiver bulk_regular_insert plugin */";  # trace

   MKDEBUG && _d("Bulk regular insert:", $sql);
   $dbh->do($sql);

   return;
}

sub custom_sth_bulk {
   my ( $self, %args ) = @_;
   my $dbh = $self->{dbh};

   # The fake sth must bind 1 var because mk-archiver is going to
   # execute it with 1 var: the bulk insert filename.  If we don't
   # fake that 1 var we'll get this error: DBD::mysql::st execute failed:
   # called with 1 bind variables when 0 are needed [for Statement "SELECT 1"]
   # at mk-archiver line 4100.
   my $sql = "SELECT ?";
   MKDEBUG && _d("Custom sth bulk:", $sql);

   my $sth = $dbh->prepare($sql);
   return $sth;
}

sub after_finish {
   my ( $self ) = @_;
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
