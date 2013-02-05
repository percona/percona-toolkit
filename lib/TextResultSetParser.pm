# This program is copyright 2008-2011 Percona Ireland Ltd.
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
# TextResultSetParser package
# ###########################################################################
{
# Package: TextResultSetParser
# TextResultSetParser converts a text result set to a data struct like
# DBI::selectall_arrayref().  Text result sets are like what SHOW PROCESSLIST
# and EXPLAIN print, like:
# 
#   +----+------+
#   | Id | User |
#   +----+------+
#   | 1  | bob  |
#   +----+------+
# 
# That converts to:
# (start code)
#   [
#      {
#         Id   => '1',
#         User => 'bob',
#      },
#   ]
# (end code)
# Both horizontal and vertical (\G) text outputs are supported.
package TextResultSetParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Optional Arguments:
#   value_for - Hashref of original_val => new_val, used to alter values
#   NAME_lc   - Lowercase key names, like $dbh->{FetchHashKeyName} = 'NAME_lc'
#
# Returns:
#   TextResultSetParser object
sub new {
   my ( $class, %args ) = @_;
   my %value_for = (
      'NULL' => undef,  # DBI::selectall_arrayref() does this
      ($args{value_for} ? %{$args{value_for}} : ()),
   );
   my $self = {
      %args,
      value_for => \%value_for,
   };
   return bless $self, $class;
}

# Sub: _pasre_tabular
#   Parse a line from tabular horizontal output.
#
# Parameters:
#   $text - Text row from horizontal output, split in <parse_horizontal_rows()>
#   @cols - Column names that text rows are organized by
#
# Returns:
#   A record hashref
sub _parse_tabular {
   my ( $text, @cols ) = @_;
   my %row;
   my @vals = $text =~ m/\| +([^\|]*?)(?= +\|)/msg;
   return (undef, \@vals) unless @cols;
   @row{@cols} = @vals;
   return (\%row, undef);
}

# Sub: _pasre_tabular
#   Parse a line from tab-separated horizontal output.
#
# Parameters:
#   $text - Text row from horizontal output, split in <parse_horizontal_rows()>
#   @cols - Column names that text rows are organized by
#
# Returns:
#   A record hashref
sub _parse_tab_sep {
   my ( $text, @cols ) = @_;
   my %row;
   my @vals = split(/\t/, $text);
   return (undef, \@vals) unless @cols;
   @row{@cols} = @vals;
   return (\%row, undef);
}

# Sub: parse_vertical_row
#   Parse records split from vertical output by <split_vertical_rows()>.
#
# Parameters:
#   $text - Text record
#
# Returns:
#   A record hashref
sub parse_vertical_row {
   my ( $self, $text ) = @_;
   my %row = $text =~ m/^\s*(\w+):(?: ([^\n]*))?/msg;
   if ( $self->{NAME_lc} ) {
      my %lc_row = map {
         my $key = lc $_;
         $key => $row{$_};
      } keys %row;
      return \%lc_row;
   }
   else {
      return \%row;
   }
}

# Sub: parse
#   Parse a text result set.
#
# Parameters:
#   $text - Text result set
#
# Returns:
#   Arrayref like:
#   (start code)
#   [
#     {
#       Time     => '5',
#       Command  => 'Query',
#       db       => 'foo',
#     },
#   ]
#   (end code)
sub parse {
   my ( $self, $text ) = @_;
   my $result_set;

   # Detect text type: tabular, tab-separated, or vertical
   if ( $text =~ m/^\+---/m ) { # standard "tabular" output
      PTDEBUG && _d('Result set text is standard tabular');
      my $line_pattern  = qr/^(\| .*)[\r\n]+/m;
      $result_set
         = $self->parse_horizontal_row($text, $line_pattern, \&_parse_tabular);
   }
   elsif ( $text =~ m/^\w+\t\w+/m ) { # tab-separated
      PTDEBUG && _d('Result set text is tab-separated');
      my $line_pattern  = qr/^(.*?\t.*)[\r\n]+/m;
      $result_set
         = $self->parse_horizontal_row($text, $line_pattern, \&_parse_tab_sep);
   }
   elsif ( $text =~ m/\*\*\* \d+\. row/ ) { # "vertical" output
      PTDEBUG && _d('Result set text is vertical (\G)');
      foreach my $row ( split_vertical_rows($text) ) {
         push @$result_set, $self->parse_vertical_row($row);
      }
   }
   else {
      my $text_sample = substr $text, 0, 300;
      my $remaining   = length $text > 300 ? (length $text) - 300 : 0;
      chomp $text_sample;
      die "Cannot determine if text is tabular, tab-separated or vertical:\n"
         . "$text_sample\n"
         . ($remaining ? "(not showing last $remaining bytes of text)\n" : "");
   }

   # Convert values.
   if ( $self->{value_for} ) {
      foreach my $result_set ( @$result_set ) {
         foreach my $key ( keys %$result_set ) {
            next unless defined $result_set->{$key};
            $result_set->{$key} = $self->{value_for}->{ $result_set->{$key} }
               if exists $self->{value_for}->{ $result_set->{$key} };
         }
      }
   }

   return $result_set;
}


# Sub: parse_horizontal_row
#   Parse rows from horizontal output (regular MySQL style output).
#
# Parameters:
#   $text         - Text result set
#   $line_pattern - Compiled regex pattern that matches one line
#   $sub          - Coderef to parse a line (tabular or tab-separated lines)
#
# Returns:
#   Arrayref of records as hashrefs
sub parse_horizontal_row {
   my ( $self, $text, $line_pattern, $sub ) = @_;
   my @result_sets = ();
   my @cols        = ();
   foreach my $line ( $text =~ m/$line_pattern/g ) {
      my ( $row, $cols ) = $sub->($line, @cols);
      if ( $row ) {
         push @result_sets, $row;
      }
      else {
         @cols = map { $self->{NAME_lc} ? lc $_ : $_ } @$cols;
      }
   }
   return \@result_sets;
}

# Sub: parse_horizontal_row
#   Split records in vertical output (\G style output).
#
# Parameters:
#   $text - Text result set
#
# Returns:
#   Array of text records, parsed by <parse_vertical_row()>.
sub split_vertical_rows {
   my ( $text ) = @_;
   my $ROW_HEADER = '\*{3,} \d+\. row \*{3,}';
   my @rows = $text =~ m/($ROW_HEADER.*?)(?=$ROW_HEADER|\z)/omgs;
   return @rows;
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
# End TextResultSetParser package
# ###########################################################################
