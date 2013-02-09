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
# QueryIterator package
# ###########################################################################
{
package QueryIterator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Mo;

has 'parser' => (
   is       => 'ro',
   isa      => 'Object',
   required => 1,
);

has 'oktorun' => (
   is       => 'ro',
   isa      => 'CodeRef',
   required => 1,
);

has 'database' => (
   is       => 'rw',
   isa      => 'Maybe[Str]',
   required => 0,
);

has 'filter' => (
   is       => 'ro',
   isa      => 'CodeRef',
   required => 0,
);

has 'read_only' => (
   is       => 'ro',
   isa      => 'Bool',
   required => 0,
   default  => 0,
);

sub BUILDARGS {

   my $filter_code;
   if ( my $filter = $args{filter} ) {
      if ( -f $filter && -r $filter ) {
         PTDEBUG && _d('Reading file', $filter, 'for --filter code');
         open my $fh, "<", $filter or die "Cannot open $filter: $OS_ERROR";
         $filter = do { local $/ = undef; <$fh> };
         close $fh;
      }
      else {
         $filter = "( $filter )";  # issue 565
      }
      my $code   = "sub { PTDEBUG && _d('callback: filter');  my(\$event) = shift; $filter && return \$event; };";
      PTDEBUG && _d('--filter code:', $code);
      $filter_code = eval $code
         or die "Error compiling --filter code: $code\n$EVAL_ERROR";
   }
   else {
      $filter_code = sub { return 1 };
   }

}

sub next {
   my ($self) = @_;

   EVENT:
   while (
      $self->oktorun()
      &&  (my $event = $parser->parse_event(%args))
   ) {

      $self->stats->{events}++;

      if ( ($event->{cmd} || '') ne 'Query' ) {
         PTDEBUG && _d('Skipping non-Query cmd');
         $stats->{not_query}++;
         next EVENT;
      }

      if ( !$event->{arg} ) {
         PTDEBUG && _d('Skipping empty arg');
         $stats->{empty_query}++;
         next EVENT;
      }

      next EVENT unless $self->filter->();
   
      if ( $self->read_only ) {
         if ( $event->{arg} !~ m/(?:^SELECT|(?:\*\/\s*SELECT))/i ) {
            PTDEBUG && _d('Skipping non-SELECT query');
            $stats->{not_select}++;
            next EVENT;
         }
      }

      $event->{fingerprint} = $qr->fingerprint($event->{arg});

      my $db = $event->{db} || $event->{Schema} || $hosts->[0]->{dsn}->{D};
      if ( $db && (!$current_db || $db ne $current_db) ) {
         $self->database($db);
      }
      else {
         $self->database(undef);
      }

      return $event;
   } # EVENT

   return;
}

no Mo;
1;
}
# ###########################################################################
# End QueryIterator package
# ###########################################################################
