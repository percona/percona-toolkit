# This program is copyright 2011 Percona Ireland Ltd.
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
# OobNibbleIterator package
# ###########################################################################
{
# Package: OobNibbleIterator
# OobNibbleIterator is a <NibbleIterator> that nibbles values which are
# out-of-bounds: beyond the lower and upper boundaries.  NibbleIterator
# nibbles a table from its lowest to its highest value, but sometimes
# another server's copy of the table might have more values below or above
# the first table's boundaires.  When the parent NibbleIterator is done,
# this class executes two more nibbles for values past the lower boundary
# and past the upper boundary.
package OobNibbleIterator;
use base 'NibbleIterator';

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Sub: new
#
# Required Arguments:
#   See <NibbleIterator::new()>
#
# Returns:
#   OobNibbleIterator object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   # Let the parent do all the init work.
   my $self = $class->SUPER::new(%args);

   my $q     = $self->{Quoter};
   my $o     = $self->{OptionParser};
   my $where = $o->has('where') ? $o->get('where') : undef;

   # If it's not a single nibble table, init our special statements.
   if ( !$self->one_nibble() ) {
      # Make statements for the lower and upper ranges.
      my $head_sql
         = ($args{past_dml} || "SELECT ")
         . ($args{past_select}
            || join(', ', map { $q->quote($_) } @{$self->{sql}->{columns}}))
         . " FROM "  . $self->{sql}->{from};

      my $tail_sql
         = ($where ? " AND ($where)" : '')
         . " ORDER BY " . $self->{sql}->{order_by};

      my $past_lower_sql
         = $head_sql
         . " WHERE " . $self->{sql}->{boundaries}->{'<'}
         . $tail_sql
         . " /*past lower chunk*/";
      PTDEBUG && _d('Past lower statement:', $past_lower_sql);

      my $explain_past_lower_sql
         = "EXPLAIN SELECT "
         . ($args{past_select}
            || join(', ', map { $q->quote($_) } @{$self->{sql}->{columns}}))
         . " FROM "  . $self->{sql}->{from}
         . " WHERE " . $self->{sql}->{boundaries}->{'<'}
         . $tail_sql
         . " /*explain past lower chunk*/";
      PTDEBUG && _d('Past lower statement:', $explain_past_lower_sql);

      my $past_upper_sql
         = $head_sql
         . " WHERE " . $self->{sql}->{boundaries}->{'>'}
         . $tail_sql
         . " /*past upper chunk*/";
      PTDEBUG && _d('Past upper statement:', $past_upper_sql);
      
      my $explain_past_upper_sql
         = "EXPLAIN SELECT "
         . ($args{past_select}
            || join(', ', map { $q->quote($_) } @{$self->{sql}->{columns}}))
         . " FROM "  . $self->{sql}->{from}
         . " WHERE " . $self->{sql}->{boundaries}->{'>'}
         . $tail_sql
         . " /*explain past upper chunk*/";
      PTDEBUG && _d('Past upper statement:', $explain_past_upper_sql);

      $self->{past_lower_sql}         = $past_lower_sql;
      $self->{past_upper_sql}         = $past_upper_sql;
      $self->{explain_past_lower_sql} = $explain_past_lower_sql;
      $self->{explain_past_upper_sql} = $explain_past_upper_sql;

      $self->{past_nibbles} = [qw(lower upper)];
      if ( my $nibble = $args{resume} ) {
         if (    !defined $nibble->{lower_boundary}
              || !defined $nibble->{upper_boundary} ) {
            # One or the other boundary isn't defined, so the last chunk
            # we're resuming from is one our oob chunks.  The parent doesn't
            # have any more bounded boundaries, and if the lower boundary
            # isn't defined then it's the lower oob chunk, so only do the
            # upper oob chunk, or if the upper boundary isn't defined, then
            # we're resuming from the upper oob chunk so we're already done.
            $self->{past_nibbles} = !defined $nibble->{lower_boundary}
                                  ? ['upper']
                                  : [];
         }
      }
      PTDEBUG && _d('Nibble past', @{$self->{past_nibbles}});

   } # not one nibble

   return bless $self, $class;
}

sub more_boundaries {
   my ($self) = @_;
   return $self->SUPER::more_boundaries() if $self->{one_nibble};
   return scalar @{$self->{past_nibbles}} ? 1 : 0;
}

sub statements {
   my ($self) = @_;

   # Get the parent's statements.
   my $sths = $self->SUPER::statements();

   # Add our special statements. 
   $sths->{past_lower_boundary} = $self->{past_lower_sth};
   $sths->{past_upper_boundary} = $self->{past_upper_sth};

   return $sths;
}

sub _prepare_sths {
   my ($self) = @_;
   PTDEBUG && _d('Preparing out-of-bound statement handles');

   # Prepare our statements for nibbles past the lower and upper boundaries.
   if ( !$self->{one_nibble} ) {
      my $dbh = $self->{Cxn}->dbh();
      $self->{past_lower_sth}         = $dbh->prepare($self->{past_lower_sql});
      $self->{past_upper_sth}         = $dbh->prepare($self->{past_upper_sql});
      $self->{explain_past_lower_sth} = $dbh->prepare($self->{explain_past_lower_sql});
      $self->{explain_past_upper_sth} = $dbh->prepare($self->{explain_past_upper_sql});
   }

   # Let the parent prepare its statements.
   return $self->SUPER::_prepare_sths();
}

sub _next_boundaries {
   my ($self) = @_;

   # Use the parent's boundaries.
   return $self->SUPER::_next_boundaries() unless $self->{no_more_boundaries};

   # Parent has no more boundaries.  Use our past boundaries.
   if ( my $past = shift @{$self->{past_nibbles}} ) {
      if ( $past eq 'lower' ) {
         PTDEBUG && _d('Nibbling values below lower boundary');
         $self->{nibble_sth}         = $self->{past_lower_sth};
         $self->{explain_nibble_sth} = $self->{explain_past_lower_sth};
         $self->{lower}              = [];
         $self->{upper}              = $self->boundaries()->{first_lower};
         $self->{next_lower}         = undef;
      }
      elsif ( $past eq 'upper' ) {
         PTDEBUG && _d('Nibbling values above upper boundary');
         $self->{nibble_sth}         = $self->{past_upper_sth};
         $self->{explain_nibble_sth} = $self->{explain_past_upper_sth};
         $self->{lower}              = $self->boundaries()->{last_upper};
         $self->{upper}              = [];
         $self->{next_lower}         = undef;
      }
      else {
         die "Invalid past nibble: $past";
      }
      return 1; # continue nibbling
   }

   PTDEBUG && _d('Done nibbling past boundaries');
   return; # stop nibbling
}

sub DESTROY {
   my ( $self ) = @_;
   foreach my $key ( keys %$self ) {
      if ( $key =~ m/_sth$/ ) {
         PTDEBUG && _d('Finish', $key);
         $self->{$key}->finish();
      }
   }
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
}
# ###########################################################################
# End OobNibbleIterator package
# ###########################################################################
