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

use POSIX qw(signal_h);
use Data::Dumper;

use Lmo;

##
# Required
##

has 'file_iter' => (
   is       => 'ro',
   isa      => 'CodeRef',
   required => 1,
);

has 'parser' => (
   is       => 'ro',
   isa      => 'CodeRef',
   required => 1,
);

has 'fingerprint' => (
   is       => 'ro',
   isa      => 'CodeRef',
   required => 1,
);

has 'oktorun' => (
   is       => 'ro',
   isa      => 'CodeRef',
   required => 1,
);

##
# Optional
##

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

has 'read_timeout' => (
   is       => 'ro',
   isa      => 'Int',
   required => 0,
   default  => 0,
);

has 'progress' => (
   is       => 'ro',
   isa      => 'Maybe[Str]',
   required => 0,
   default  => sub { return },
);

##
# Private
##

has '_progress' => (
   is       => 'rw',
   isa      => 'Maybe[Object]',
   required => 0,
   default  => sub { return },
);

has 'stats' => (
   is       => 'ro',
   isa      => 'HashRef',
   required => 0,
   default  => sub { return {} },
);

has '_fh' => (
   is       => 'rw',
   isa      => 'Maybe[FileHandle]',
   required => 0,
);

has '_file_name' => (
   is       => 'rw',
   isa      => 'Maybe[Str]',
   required => 0,
);

has '_file_size' => (
   is       => 'rw',
   isa      => 'Maybe[Int]',
   required => 0,
);

has '_offset' => (
   is       => 'rw',
   isa      => 'Maybe[Int]',
   required => 0,
);

has '_parser_args' => (
   is       => 'rw',
   isa      => 'HashRef',
   required => 0,
);

sub BUILDARGS {
   my $class = shift;
   my $args  = $class->SUPER::BUILDARGS(@_);

   my $filter_code;
   if ( my $filter = $args->{filter} ) {
      if ( -f $filter && -r $filter ) {
         PTDEBUG && _d('Reading file', $filter, 'for --filter code');
         open my $fh, "<", $filter or die "Cannot open $filter: $OS_ERROR";
         $filter = do { local $/ = undef; <$fh> };
         close $fh;
      }
      else {
         $filter = "( $filter )";  # issue 565
      }
      my $code = "sub {
         PTDEBUG && _d('callback: filter');
         my(\$event) = shift;
         $filter && return \$event;
      };";
      PTDEBUG && _d('--filter code:', $code);
      $filter_code = eval $code
         or die "Error compiling --filter code: $code\n$EVAL_ERROR";
   }
   else {
      $filter_code = sub { return 1 };
   }

   my $self = {
      %$args,
      filter => $filter_code,
   };

   return $self;
}

sub next {
   my ($self) = @_;

   if ( !$self->_fh ) {
      my ($fh, $file_name, $file_size) = $self->file_iter->();
      return unless $fh;

      PTDEBUG && _d('Reading', $file_name);
      $self->_fh($fh);
      $self->_file_name($file_name);
      $self->_file_size($file_size);

      my $parser_args = {};

      if ( my $read_timeout = $self->read_timeout ) {
         $parser_args->{next_event}
            = sub { return _read_timeout($fh, $read_timeout); };
      }
      else {
         $parser_args->{next_event} = sub { return <$fh>; };
      }

      $parser_args->{tell} = sub {
         my $offset = tell $fh;  # update global $offset
         $self->_offset($offset);
         return $offset;  # legacy: return global $offset
      };

      my $_progress;
      if ( my $spec = $self->progress ) {
         $_progress = new Progress(
            jobsize => $file_size,
            spec    => $spec,
            name    => $file_name,
         );
      }
      $self->_progress($_progress);

      $self->_parser_args($parser_args);
   }

   EVENT:
   while (
      $self->oktorun
      &&  (my $event = $self->parser->(%{ $self->_parser_args }) )
   ) {
      $self->stats->{queries_read}++;

      if ( my $pr = $self->_progress ) {
         $pr->update($self->_parser_args->{tell});
      }

      if ( ($event->{cmd} || '') ne 'Query' ) {
         PTDEBUG && _d('Skipping non-Query cmd');
         $self->stats->{not_query}++;
         next EVENT;
      }

      if ( !$event->{arg} ) {
         PTDEBUG && _d('Skipping empty arg');
         $self->stats->{empty_query}++;
         next EVENT;
      }

      if ( !$self->filter->($event) ) {
         $self->stats->{queries_filtered}++;
         next EVENT;
      }

      if ( $self->read_only ) {
         if ( $event->{arg} !~ m{^(?:/\*[^!].*?\*/)?\s*(?:SELECT|SET)}i ) {
            PTDEBUG && _d('Skipping non-SELECT query');
            $self->stats->{not_select}++;
            next EVENT;
         }
      }

      $event->{fingerprint} = $self->fingerprint->($event->{arg});

      return $event;
   }

   PTDEBUG && _d('Done reading', $self->_file_name);
   close $self->_fh if $self->_fh;
   $self->_fh(undef);
   $self->_file_name(undef);
   $self->_file_size(undef);

   return;
}

# Read the fh and timeout after t seconds.
sub _read_timeout {
   my ( $fh, $t ) = @_;
   return unless $fh;
   $t ||= 0;  # will reset alarm and cause read to wait forever

   # Set the SIGALRM handler.
   my $mask   = POSIX::SigSet->new(&POSIX::SIGALRM);
   my $action = POSIX::SigAction->new(
      sub {
         # This sub is called when a SIGALRM is received.
         die 'read timeout';
      },
      $mask,
   );
   my $oldaction = POSIX::SigAction->new();
   sigaction(&POSIX::SIGALRM, $action, $oldaction);

   my $res;
   eval {
      alarm $t;
      $res = <$fh>;
      alarm 0;
   };
   if ( $EVAL_ERROR ) {
      PTDEBUG && _d('Read error:', $EVAL_ERROR);
      die $EVAL_ERROR unless $EVAL_ERROR =~ m/read timeout/;
      $res = undef;  # res is a blank string after a timeout
   }
   return $res;
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
# End QueryIterator package
# ###########################################################################
