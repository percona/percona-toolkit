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
# EventExecutor package
# ###########################################################################
{
package EventExecutor;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Time::HiRes qw(time);
use Data::Dumper;

use Lmo;

has 'default_database' => (
   is       => 'rw',
   isa      => 'Maybe[Str]',
   required => 0,
);

##
# Private
##

has 'stats' => (
   is       => 'ro',
   isa      => 'HashRef',
   required => 0,
   default  => sub { return {} },
);

sub exec_event {
   my ($self, %args) = @_;
   my @required_args = qw(host event);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $host  = $args{host};
   my $event = $args{event};

   my $results = {
      query_time => undef,
      sth        => undef,
      warnings   => undef,
      error      => undef,
   };

   eval {
      my $db = $event->{db} || $event->{Schema} || $self->default_database;
      if ( $db && (!$host->{current_db} || $host->{current_db} ne $db) ) {
         PTDEBUG && _d('New current db:', $db);
         $host->dbh->do("USE `$db`");
         $host->{current_db} = $db;
      }
      my $sth = $host->dbh->prepare($event->{arg});
      my $t0 = time;
      $sth->execute();
      my $t1 = time - $t0;
      $results->{query_time} = sprintf('%.6f', $t1);
      $results->{sth}        = $sth;
      $results->{warnings}   = $self->get_warnings(dbh => $host->dbh);
   };
   if ( my $e = $EVAL_ERROR ) {
      PTDEBUG && _d($e);
      chomp($e);
      $e =~ s/ at \S+ line \d+, \S+ line \d+\.$//;
      $results->{error} = $e;
   }
   PTDEBUG && _d('Result on', $host->name, Dumper($results));
   return $results;
}

sub get_warnings {
   my ($self, %args) = @_;
   my @required_args = qw(dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $dbh = $args{dbh};
   my $warnings = $dbh->selectall_hashref('SHOW WARNINGS', 'code');
   return $warnings;
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
# End EventExecutor package
# ###########################################################################
