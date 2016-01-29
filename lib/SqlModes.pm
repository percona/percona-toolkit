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
# SqlModes package
# ###########################################################################
{
# Package: SqlModes
# SqlModes is a simple module that helps add/delete elements to the sql_mode 
# variable in MySql.
package SqlModes;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;

# Sub: new
#
# Required Arguments:
#   dbh     - Database where to apply changes
#
# Returns:
#   SqlModes object 

sub new {
   my ( $class, $dbh, %args ) = @_;
   die "I need a database handle" unless $dbh;

   my $global = $args{'global'} ? 'GLOBAL' : '';

   my $self = {
      dbh => $dbh, 
      global => $global,
      original_modes_string => '',
   };

   bless $self, $class;

   $self->{original_modes_string} = $self->get_modes_string();
   return $self;
}


# Sub: set_mode_string 
#   sets sql_mode in traditional csv format 
#
#   Required Arguments:
#     string of valid formats in csv formta (or null string)      
#
# Returns:
#   1 if successful, 0 if error.
sub set_mode_string {
   my ( $self, $sql_mode_string ) = @_;

   die "I need a string" unless defined $sql_mode_string;

   $self->{dbh}->do("set $self->{global} sql_mode = '$sql_mode_string'") || return 0;

   PTDEBUG && _d('sql_mode changed to: ', $sql_mode_string);
   return 1;
}

# Sub: add
#   adds one or more modes 
#
#   Required Arguments:
#     list of sql modes      
#
# Returns:
#   1 if successful, 0 if error.
sub add {
   my ( $self, @args ) = @_;

   die "I need at least one sql mode as an argument" unless @args;

   my $curr_modes = $self->get_modes();

   foreach my $mode (@args) {
      $curr_modes->{$mode} = 1;
      PTDEBUG && _d('adding sql_mode: ', $mode);
   }

   my $sql_mode_string = join ",", keys %$curr_modes; 

   $self->{dbh}->do("set $self->{global} sql_mode = '$sql_mode_string'") || return 0;

   PTDEBUG && _d('sql_mode changed to: ', $sql_mode_string);
   return $curr_modes;
}

# Sub: del
#     remove one or more modes
#
#   Required Arguments:
#     list of sql modes      
#
# Returns:
#   1 if successful, 0 if error.
sub del {
   my ( $self, @args ) = @_;

   die "I need at least one sql mode as an argument" unless @args;

   my $curr_modes = $self->get_modes();

   foreach my $mode (@args) {
      delete $curr_modes->{$mode};
      PTDEBUG && _d('deleting sql_mode: ', $mode);
   }

   my $sql_mode_string = join ",", keys %$curr_modes; 

   $self->{dbh}->do("SET $self->{global} sql_mode = '$sql_mode_string'") || return 0;

   PTDEBUG && _d('sql_mode changed to: ', $sql_mode_string);
   return $curr_modes || 1;
}

# Sub: has_mode 
#   checks if a mode is on. (exists within the sql_mode string) 
#
#   Required Arguments:
#     1 mode string 
#
# Returns:
#   1 = yes , 0 = no
sub has_mode {
   my ( $self, $mode ) = @_;

   die "I need a mode to check" unless $mode;

   my (undef, $sql_mode_string) = $self->{dbh}->selectrow_array("show variables like 'sql_mode'");

   # Need to account for occurrance at 
   # beginning, middle or end of comma separated string
   return $sql_mode_string =~ /(?:,|^)$mode(?:,|$)/;

}

# Sub: get_modes
#   get current set of sql modes 
#
#   Required Arguments:
#     none
#
# Returns:
#   ref to hash with mode names as keys assigned value 1.
sub get_modes {
   my ( $self ) = @_;

   my (undef, $sql_mode_string) = $self->{dbh}->selectrow_array("show variables like 'sql_mode'");

   my @modes = split /,/, $sql_mode_string;

   my %modes;
   foreach my $m (@modes) {
      $modes{$m} = 1;
   }

   return \%modes;
}

# Sub: get_modes_string
#   get current set of sql modes as string 
#
#   Required Arguments:
#     none
#
# Returns:
#   sql_modes as a string (coma separated values) 
sub get_modes_string {
   my ( $self ) = @_;

   my (undef, $sql_mode_string) = $self->{dbh}->selectrow_array("show variables like 'sql_mode'");

   return $sql_mode_string;
}

# Sub: restore_original_modes 
#   resets sql_mode to the state it was when object was created 
#
#   Required Arguments:
#     none
#
# Returns:
#   original sql_mode as a string
sub restore_original_modes {
   my ( $self ) = @_;

   $self->{dbh}->do("SET $self->{global} sql_mode = '$self->{original_modes_string}'");

   return $self->{original_modes_string};
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
# End SqlModes package
# ###########################################################################
