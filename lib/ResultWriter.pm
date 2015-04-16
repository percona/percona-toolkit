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
# ResultWriter package
# ###########################################################################
{
package ResultWriter;

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

has 'pretty' => (
    is       => 'ro',
    isa      => 'Bool',
    required => 0,
    default  => 0,
);

has 'default_database' => (
   is       => 'rw',
   isa      => 'Maybe[Str]',
   required => 0,
);

has 'current_database' => (
   is       => 'rw',
   isa      => 'Maybe[Str]',
   required => 0,
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

   my $query_file = "$dir/query";
   open my $_query_fh, '>', $query_file
      or die "Cannot open $query_file for writing: $OS_ERROR";

   my $results_file = "$dir/results";
   open my $_results_fh, '>', $results_file
      or die "Cannot open $results_file for writing: $OS_ERROR";

   my $rows_file = "$dir/rows";
   open my $_rows_fh, '>', $rows_file
      or die "Cannot open $rows_file for writing: $OS_ERROR";

   my $self = {
      %$args,
      _query_fh   => $_query_fh,
      _results_fh => $_results_fh,
      _rows_fh    => $_rows_fh,
   };

   return $self;
}


sub save {
   my ($self, %args) = @_;

   my $host    = $args{host};
   my $event   = $args{event};
   my $results = $args{results};

   # Save the query.
   my $current_db = $self->current_database;
   my $db = $event->{db} || $event->{Schema} || $self->default_database;
   if ( $db && (!$current_db || $current_db ne $db) ) {
      PTDEBUG && _d('New current db:', $db);
      print { $self->_query_fh } "use `$db`;\n";
      $self->current_database($db);
   }
   print { $self->_query_fh } $event->{arg}, "\n##\n";

   if ( my $error = $results->{error} ) {
      # Save the error.
      print { $self->_results_fh }
         $self->dumper({ error => $error}, 'results'), "\n##\n";

      # Save empty rows.
      print { $self->_rows_fh } "\n##\n";
   }
   else {
      # Save rows, if any (i.e. if it's a SELECT statement).
      # *except* if it's a SELECT...INTO (issue lp:1421781) 
      my $rows;
      if ( my $sth = $results->{sth} ) {
         if ( $event->{arg} =~ m/(?:^\s*SELECT|(?:\*\/\s*SELECT))/i 
            &&  $event->{arg} !~ /INTO\s*(?:OUTFILE|DUMPFILE|@)/ ) {
            $rows = $sth->fetchall_arrayref();
         }
         eval {
            $sth->finish;
         };
         if ( $EVAL_ERROR ) {
            PTDEBUG && _d($EVAL_ERROR);
         }
      }
      print { $self->_rows_fh }
         ($rows ? $self->dumper($rows, 'rows') : ''), "\n##\n";

      # Save results.
      delete $results->{error};
      delete $results->{sth};
      print { $self->_results_fh } $self->dumper($results, 'results'), "\n##\n";
   }

   return;
}

sub dumper {
   my ($self, $data, $name) = @_;
   if ( $self->pretty ) {
      local $Data::Dumper::Indent    = 1;
      local $Data::Dumper::Sortkeys  = 1;
      local $Data::Dumper::Quotekeys = 0;
      return Data::Dumper->Dump([$data], [$name]);
   }
   else {
      local $Data::Dumper::Indent    = 0;
      local $Data::Dumper::Sortkeys  = 0;
      local $Data::Dumper::Quotekeys = 0;
      return Data::Dumper->Dump([$data], [$name]);
   }
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
# End ResultWriter package
# ###########################################################################
