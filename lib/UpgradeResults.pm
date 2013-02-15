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
# UpgradeResults package
# ###########################################################################
{
package UpgradeResults;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Digest::MD5 qw(md5_hex);

use Lmo;

has 'max_class_size' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has 'max_examples' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has 'classes' => (
    is       => 'rw',
    isa      => 'HashRef',
    required => 0,
    default  => sub { return {} },
);

sub save_diffs {
   my ($self, %args) = @_;

   my $event           = $args{event};
   my $query_time_diff = $args{query_time_diff};
   my $warning_diffs   = $args{warning_diffs};
   my $row_diffs       = $args{row_diffs};

   my $class = $self->class(event => $event);

   if ( my $query = $self->_can_save(event => $event, class => $class) ) {

      if ( $query_time_diff
           && scalar @{$class->{query_time_diffs}} < $self->max_examples ) {
         push @{$class->{query_time_diffs}}, [
            $query,
            $query_time_diff,
         ];
      }

      if ( @$warning_diffs
           && scalar @{$class->{warning_diffs}} < $self->max_examples ) {
         push @{$class->{warnings_diffs}}, [
            $query,
            $warning_diffs,
         ];
      }

      if ( @$row_diffs
           && scalar @{$class->{row_diffs}} < $self->max_examples ) {
         push @{$class->{row_diffs}}, [
            $query,
            $row_diffs,
         ];
      }
   }

   return;
}

sub save_error {
   my ($self, %args) = @_;

   my $event  = $args{event};
   my $error1 = $args{error1};
   my $error2 = $args{error2};

   my $class = $self->class(event => $event);

   if ( my $query = $self->_can_save(event => $event, class => $class) ) {
      if ( scalar @{$class->{errors}} < $self->max_examples ) {
         push @{$class->{errors}}, [
            $query,
            $error1,
            $error2,
         ];
      }
   }

   return;
}

sub _can_save {
   my ($self, %args) = @_;
   my $event = $args{event};
   my $class = $args{class};
   my $query = $event->{arg};
   if ( exists $class->{unique_queries}->{$query}
        || scalar keys %{$class->{unique_queries}} < $self->max_class_size ) {
      $class->{unique_queries}->{$query}++;
      return $query;
   }
   PTDEBUG && _d('Too many queries in class, discarding', $query);
   $class->{discarded}++;
   return;
}

sub class {
   my ($self, %args) = @_;
   my $event = $args{event};

   my $id      = uc(substr(md5_hex($event->{fingerprint}), -16));
   my $classes = $self->classes;
   my $class   = $classes->{$id};
   if ( !$class ) {
      PTDEBUG && _d('New query class:', $id, $event->{fingerprint});
      $class = $self->_new_class(
         id    => $id,
         event => $event,
      );
      $classes->{$id} = $class;
   }
   return $class;
}

sub _new_class {
   my ($self, %args) = @_;
   my $id    = $args{id};
   my $event = $args{event};
   PTDEBUG && _d('New query class:', $id, $event->{fingerprint});
   my $class = {
      id               => $id,
      fingerprint      => $event->{fingerprint},
      discarded        => 0,
      unique_queries   => {
         $event->{arg} => 0,
      },
      query_time_diffs => [], 
      warning_diffs    => [],
      row_diffs        => [],
   };
   return $class;
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
# End UpgradeResults package
# ###########################################################################
