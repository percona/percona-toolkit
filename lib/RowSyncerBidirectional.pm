# This program is copyright 2011 Percona Inc.
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
# RowSyncerBidirectional package
# ###########################################################################
{
# Package: RowSyncerBidirectional
# RowSyncerBidirectional syncs a destination row to a source row.
package RowSyncerBidirectional;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant UPDATE_LEFT      => -1;
use constant UPDATE_RIGHT     =>  1;
use constant UPDATE_NEITHER   =>  0;  # neither value equals/matches
use constant FAILED_THRESHOLD =>  2;  # failed to exceed threshold

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(OptionParser ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = {
      crc_col => 'crc',
      %args,
   };
   return bless $self, $class;
}

sub set_crc_col {
   my ($self, $crc_col) = @_;
   $self->{crc_col} = $crc_col;
   return;
}

sub set_key_cols {
   my ($self, $key_cols) = @_;
   $self->{key_cols} = $key_cols;
   return;
}

sub key_cols {
   my ($self) = @_;
   return $self->{key_cols};
}

# Sub: cmd_conflict_col
#   Compare --conflict-column values for --bidirectional.  This sub is
#   used as a callback in <set_bidirectional_callbacks()>.
#
# Parameters:
#   $left_val  - Column value from left (usually the source host)
#   $right_val - Column value from right (usually the destination host)
#   $cmp       - Type of conflict comparison, --conflict-comparison
#   $val       - Value for certain types of comparisons, --conflict-value
#   $thr       - Threshold for certain types of comparisons,
#                --conflict-threshold
#
# Returns:
#   One of the constants above, UPDATE_* or FAILED_THRESHOLD
sub cmp_conflict_col {
   my ( $left_val, $right_val, $cmp, $val, $thr ) = @_;
   MKDEBUG && _d('Compare', @_);
   my $res;
   if ( $cmp eq 'newest' || $cmp eq 'oldest' ) {
      $res = $cmp eq 'newest' ? ($left_val  || '') cmp ($right_val || '')
           :                    ($right_val || '') cmp ($left_val  || '');

      if ( $thr ) {
         $thr     = Transformers::time_to_secs($thr);
         my $lts  = Transformers::any_unix_timestamp($left_val);
         my $rts  = Transformers::any_unix_timestamp($right_val);
         my $diff = abs($lts - $rts);
         MKDEBUG && _d('Check threshold, lts rts thr abs-diff:',
            $lts, $rts, $thr, $diff);
         if ( $diff < $thr ) {
            MKDEBUG && _d("Failed threshold");
            return FAILED_THRESHOLD;
         }
      }
   }
   elsif ( $cmp eq 'greatest' || $cmp eq 'least' ) {
      $res = $cmp eq 'greatest' ? (($left_val ||0) > ($right_val ||0) ? 1 : -1)
           :                      (($left_val ||0) < ($right_val ||0) ? 1 : -1);
      $res = 0 if ($left_val || 0) == ($right_val || 0);
      if ( $thr ) {
         my $diff = abs($left_val - $right_val);
         MKDEBUG && _d('Check threshold, abs-diff:', $diff);
         if ( $diff < $thr ) {
            MKDEBUG && _d("Failed threshold");
            return FAILED_THRESHOLD;
         }
      }
   }
   elsif ( $cmp eq 'equals' ) {
      $res = ($left_val  || '') eq $val ?  1
           : ($right_val || '') eq $val ? -1
           :                               0;
   }
   elsif ( $cmp eq 'matches' ) {
      $res = ($left_val  || '') =~ m/$val/ ?  1
           : ($right_val || '') =~ m/$val/ ? -1
           :                                  0;
   }
   else {
      # Should happen; caller should have verified this.
      die "Invalid comparison: $cmp";
   }

   return $res;
}

sub same_row {
   my ($self,  %args) = @_;
   my ($lr, $rr, $syncer) = @args{qw(lr rr syncer)};

   my $ch       = $self->{ChangeHandler};
   my $action   = 'UPDATE';
   my $auth_row = $lr;
   my $change_dbh;
   my $err;
  
   my $o   = $self->{OptionParser}; 
   my $col = $o->get('conflict-column');
   my $cmp = $o->get('conflict-comparison');
   my $val = $o->get('conflict-value');
   my $thr = $o->get('conflict-threshold');

   my $left_val  = $lr->{$col} || '';
   my $right_val = $rr->{$col} || '';
   MKDEBUG && _d('left',  $col, 'value:', $left_val);
   MKDEBUG && _d('right', $col, 'value:', $right_val);

   my $res = cmp_conflict_col($left_val, $right_val, $cmp, $val, $thr);
   if ( $res == UPDATE_LEFT ) {
      MKDEBUG && _d("right dbh $args{right_dbh} $cmp; "
         . "update left dbh $args{left_dbh}");
      $ch->set_src('right', $args{right_dbh});
      $auth_row   = $args{rr};
      $change_dbh = $args{left_dbh};
   }
   elsif ( $res == UPDATE_RIGHT ) {
      MKDEBUG && _d("left dbh $args{left_dbh} $cmp; "
         . "update right dbh $args{right_dbh}");
      $ch->set_src('left', $args{left_dbh});
      $auth_row   = $args{lr};
      $change_dbh = $args{right_dbh};
   }
   elsif ( $res == UPDATE_NEITHER ) {
      if ( $cmp eq 'equals' || $cmp eq 'matches' ) {
         $err = "neither `$col` value $cmp $val";
      }
      else {
         $err = "`$col` values are the same"
      }
   }
   elsif ( $res == FAILED_THRESHOLD ) {
      $err = "`$col` values do not differ by the threhold, $thr."
   }
   else {
      # Shouldn't happen.
      die "cmp_conflict_col() returned an invalid result: $res."
   }

   if ( $err ) {
      $action   = undef;  # skip change in case we just warn
      my $where = $ch->make_where_clause($lr, $self->key_cols());
      $err      = "# Cannot resolve conflict WHERE $where: $err\n";

      # die here is caught in sync_a_table().  We're deeply nested:
      # sync_a_table > sync_table > compare_sets > syncer > here
      my $print_err = $o->get('conflict-error');
        $print_err =~ m/warn/i   ? warn $err 
      : $print_err =~ m/die/i    ? die $err
      : $print_err =~ m/ignore/i ? MKDEBUG && _d("Conflict error:", $err)
      : die "Invalid --conflict-error: $print_err";
      return;
   }

   return $ch->change(
      $action,            # Execute the action
      $auth_row,          # with these row values
      $self->key_cols(),  # identified by these key cols
      $change_dbh,        # on this dbh
   );
}

sub not_in_right {
   my ( $self, %args ) = @_;
   $self->{ChangeHandler}->set_src('left', $args{left_dbh});
   return $self->{ChangeHandler}->change(
      'INSERT',           # Execute the action
      $args{lr},          # with these row values
      $self->key_cols(),  # identified by these key cols
      $args{right_dbh},   # on this dbh
   );
}

sub not_in_left {
   my ( $self, %args ) = @_;
   $self->{ChangeHandler}->set_src('right', $args{right_dbh});
   return $self->{ChangeHandler}->change(
      'INSERT',           # Execute the action
      $args{rr},          # with these row values
      $self->key_cols(),  # identified by these key cols
      $args{left_dbh},    # on this dbh
   );
}

sub done_with_rows {
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
# End RowSyncerBidirectional package
# ###########################################################################
