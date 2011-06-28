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
# OSCCaptureSync package $Revision: 7463 $
# ###########################################################################

# Package: OSCCaptureSync
# OSCCaptureSync implements the capture and sync phases of an online schema
# change.
{
package OSCCaptureSync;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Returns:
#   OSCCaptureSync object
sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
      %args,
   };

   return bless $self, $class;
}

sub capture {
   my ( $self, %args ) = @_;
   my @required_args = qw(msg dbh db tbl tmp_tbl columns chunk_column);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($msg, $dbh) = @args{@required_args};

   my @triggers = $self->_make_triggers(%args);
   foreach my $sql ( @triggers ) {
      $msg->($sql);
      $dbh->do($sql) unless $args{print};
   }

   return;
}

sub _make_triggers {
   my ( $self, %args ) = @_;
   my @required_args = qw(db tbl tmp_tbl chunk_column columns);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($db, $tbl, $tmp_tbl, $chunk_column) = @args{@required_args};

   my $old_table  = "`$db`.`$tbl`";
   my $new_table  = "`$db`.`$tmp_tbl`";
   my $new_values = join(', ', map { "NEW.$_" } @{$args{columns}});
   my $columns    = join(', ', @{$args{columns}});

   my $delete_trigger = "CREATE TRIGGER mk_osc_del AFTER DELETE ON $old_table "
                      . "FOR EACH ROW "
                      . "DELETE IGNORE FROM $new_table "
                      . "WHERE $new_table.$chunk_column = OLD.$chunk_column";

   my $insert_trigger = "CREATE TRIGGER mk_osc_ins AFTER INSERT ON $old_table "
                      . "FOR EACH ROW "
                      . "REPLACE INTO $new_table ($columns) "
                      . "VALUES($new_values)";

   my $update_trigger = "CREATE TRIGGER mk_osc_upd AFTER UPDATE ON $old_table "
                      . "FOR EACH ROW "
                      . "REPLACE INTO $new_table ($columns) "
                      . "VALUES ($new_values)";

   return $delete_trigger, $update_trigger, $insert_trigger;
}

sub sync {
   my ( $self, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   return;
}

sub cleanup {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db msg);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $msg) = @args{@required_args};

   foreach my $trigger ( qw(del ins upd) ) {
      my $sql = "DROP TRIGGER IF EXISTS `$db`.`mk_osc_$trigger`";
      $msg->($sql);
      $dbh->do($sql) unless $args{print};
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
# End OSCCaptureSync package
# ###########################################################################
