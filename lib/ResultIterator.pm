# This program is copyright 2013 Percona Ireland Ltd.
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
# ResultIterator package
# ###########################################################################
{
package ResultIterator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;

use Lmo;

has 'dir' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'progress' => (
   is       => 'ro',
   isa      => 'Maybe[Str]',
   required => 0,
   default  => sub { return },
);

has '_progress' => (
   is       => 'rw',
   isa      => 'Maybe[Object]',
   required => 0,
   default  => sub { return },
);

has '_query_fh' => (
    is       => 'rw',
    isa      => 'Maybe[FileHandle]',
    required => 0,
);

has '_results_fh' => (
    is       => 'rw',
    isa      => 'Maybe[FileHandle]',
    required => 0,
);

has '_rows_fh' => (
    is       => 'rw',
    isa      => 'Maybe[FileHandle]',
    required => 0,
);

sub BUILDARGS {
   my $class = shift;
   my $args  = $class->SUPER::BUILDARGS(@_);

   my $dir = $args->{dir};
   die "$dir does not exist\n" unless -d $dir;

   my $query_file = "$dir/query";
   PTDEBUG && _d('Query file:', $query_file);
   open my $_query_fh, '<', $query_file
      or die "Cannot open $query_file for writing: $OS_ERROR";

   my $results_file = "$dir/results";
   PTDEBUG && _d('Meta file:', $results_file);
   open my $_results_fh, '<', $results_file
      or die "Cannot open $results_file for writing: $OS_ERROR";

   my $rows_file = "$dir/rows";
   PTDEBUG && _d('Results file:', $rows_file);
   open my $_rows_fh, '<', $rows_file
      or die "Cannot open $rows_file for writing: $OS_ERROR";

   my $_progress;
   if ( my $spec = $args->{progress} ) {
      $_progress = new Progress(
         jobsize => -s $query_file,
         spec    => $spec,
         name    => $query_file,
      );
   }

   my $self = {
      %$args,
      _query_fh   => $_query_fh,
      _results_fh => $_results_fh,
      _rows_fh    => $_rows_fh,
      _progress   => $_progress,
   };

   return $self;
}

sub next {
   my ($self, %args) = @_;

   local $INPUT_RECORD_SEPARATOR = "\n##\n";

   my $_query_fh   = $self->_query_fh;
   my $_results_fh = $self->_results_fh;
   my $_rows_fh    = $self->_rows_fh;

   my $query   = <$_query_fh>;
   my $results = <$_results_fh>;
   my $rows    = <$_rows_fh>;

   if ( !$query ) {
      PTDEBUG && _d('No more results');
      return;
   }

   chomp($query);

   if ( $results ) {
      chomp($results);
      eval $results;
   }

   if ( $rows ) {
      chomp($rows);
      eval $rows;
   }

   $query =~ s/^use ([^;]+);\n//;

   my $db = $1;
   if ( $db ) {
      $db =~ s/^`//;
      $db =~ s/`$//;
      $results->{db} = $db;
   }

   $results->{query} = $query;
   $results->{rows}  = $rows;
      
   if ( my $pr = $self->_progress ) {
      $pr->update(sub { tell $_query_fh });
   }

   PTDEBUG && _d('Results:', Dumper($results));
   return $results;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

no Lmo;
1;
}
# ###########################################################################
# End ResultIterator package
# ###########################################################################
