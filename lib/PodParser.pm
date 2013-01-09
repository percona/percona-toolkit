# This program is copyright 2010-2011 Percona Ireland Ltd.
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
# PodParser package
# ###########################################################################
{
# Package: PodParser
# PodParser parses sections of a POD.
# This package wants to subclasses Pod::Parser but because some people
# still run ancient systems on which even "core" modules are missing,
# we have to roll our own pod parser.
package PodParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# List =item from these head1 sections will be parsed into a hash
# with the item's name as the key and its paragraphs parsed as
# another hash of attribute-value pairs.  The first para is usually
# a single line of attrib: value; ..., but this is optional.  The
# other paras are the item's description, saved under the desc key.
my %parse_items_from = (
   'OPTIONS'     => 1,
   'DSN OPTIONS' => 1,
   'RULES'       => 1,
);

# Pattern to match and capture the item's name after "=item ".
my %item_pattern_for = (
   'OPTIONS'     => qr/--(.*)/,
   'DSN OPTIONS' => qr/\* (.)/,
   'RULES'       => qr/(.*)/,
);

# True if the head1 section's paragraphs before its first =item
# define rules, one per para/line.  These rules are saved in an
# arrayref under the rules key.
my %section_has_rules = (
   'OPTIONS'     => 1,
   'DSN OPTIONS' => 0,
   'RULES'       => 0,
);

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      current_section => '',
      current_item    => '',
      items           => {},  # keyed off SECTION
      magic           => {},  # keyed off SECTION->magic ident (without MAGIC_)
      magic_ident     => '',  # set when next para is a magic para
   };
   return bless $self, $class;
}
 
sub get_items {
   my ( $self, $section ) = @_;
   return $section ? $self->{items}->{$section} : $self->{items};
}

sub get_magic {
   my ( $self, $section ) = @_;
   return $section ? $self->{magic}->{$section} : $self->{magic};
}

sub parse_from_file {
   my ( $self, $file ) = @_;
   return unless $file;
   PTDEBUG && _d('Parsing POD in', $file);
   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   local $INPUT_RECORD_SEPARATOR = '';  # read paragraphs
   my $para;

   # Skip past file contents until we reach start of POD.
   1 while defined($para = <$fh>) && $para !~ m/^=pod/;
   die "$file does not contain =pod" unless $para;

   while ( defined($para = <$fh>) && $para !~ m/^=cut/ ) {
      if ( $para =~ m/^=(head|item|over|back)/ ) {
         my ($cmd, $name) = $para =~ m/^=(\w+)(?:\s+(.+))?/;
         $name ||= '';
         PTDEBUG && _d('cmd:', $cmd, 'name:', $name);
         $self->command($cmd, $name);
      }
      elsif ( $parse_items_from{$self->{current_section}} ) {
         $self->textblock($para);
      }
   }

   close $fh;
}

# Commands like =head1, =over, =item and =back.  Paragraphs following
# these command are passed to textblock().
sub command {
   my ( $self, $cmd, $name ) = @_;
   
   $name =~ s/\s+\Z//m;  # Remove \n and blank line after name.

   if  ( $cmd eq 'head1' ) {
      PTDEBUG && _d('In section', $name);
      $self->{current_section} = $name;
   }
   elsif ( $cmd eq 'over' ) {
      if ( $parse_items_from{$name} ) {
         PTDEBUG && _d('Start items in', $self->{current_section});
         $self->{items}->{$self->{current_section}} = {};
      }
   }
   elsif ( $cmd eq 'item' && $parse_items_from{$self->{current_section}} ) {
      my $pat = $item_pattern_for{ $self->{current_section} };
      my ($item) = $name =~ m/$pat/;
      if ( $item ) {
         PTDEBUG && _d($self->{current_section}, 'item:', $item);
         $self->{items}->{ $self->{current_section} }->{$item} = {
            desc => '',  # every item should have a desc
         };
         $self->{current_item} = $item;
      }
      else {
         warn "Item $name does not match $pat";
      }
   }
   elsif ( $cmd eq 'back' ) {
      if ( $parse_items_from{$self->{current_section}} ) {
         PTDEBUG && _d('End items in', $self->{current_section});
      }
   }
   else {
      $self->{current_section} = '';
   }
   
   return;
}

# Paragraphs after a command.
sub textblock {
   my ( $self, $para ) = @_;

   return unless $self->{current_section} && $self->{current_item};

   my $section = $self->{current_section};
   my $item    = $self->{items}->{$section}->{ $self->{current_item} };

   $para =~ s/\s+\Z//;

   if ( $para =~ m/^[a-z]\w+[:;] / ) {
      PTDEBUG && _d('Item attributes:', $para);
      map {
         my ($attrib, $val) = split(/: /, $_);
         $item->{$attrib} = defined $val ? $val : 1;
      } split(/; /, $para);
   }
   else {
      # Handle MAGIC (verbatim) para signal by previous call/para.
      if ( $self->{magic_ident} ) {

         # Magical paras have to be indented (because they're verbatim paras).
         my ($leading_space) = $para =~ m/^(\s+)/;
         my $indent          = length($leading_space || '');
         if ( $indent ) {
            $para =~ s/^\s{$indent}//mg;
            $para =~ s/\s+$//;
            PTDEBUG && _d("MAGIC", $self->{magic_ident}, "para:", $para);
            $self->{magic}->{$self->{current_section}}->{$self->{magic_ident}}
               = $para;
         }
         else {
            PTDEBUG && _d("MAGIC", $self->{magic_ident},
               "para is not indented; treating as normal para");
         }

         $self->{magic_ident} = '';  # must unset this!
      }

      # Save the para text to the description for this item.
      PTDEBUG && _d('Item desc:', substr($para, 0, 40),
         length($para) > 40 ? '...' : '');
      $para =~ s/\n+/ /g;
      $item->{desc} .= $para;

      # If this para contains a MAGIC identifier, the next para should be
      # an indented (verbatim) para.  We set magic_ident to signal this and
      # handle it next call in code block above.
      if ( $para =~ m/MAGIC_(\w+)/ ) {
         $self->{magic_ident} = $1;  # XXX
         PTDEBUG && _d("MAGIC", $self->{magic_ident}, "follows");
      }
   }

   return;
}

# Indented blocks of text, e.g. SYNOPSIS examples.  We don't
# do anything with these yet.
sub verbatim {
   my ( $self, $para ) = @_;
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
# End PodParser package
# ###########################################################################
