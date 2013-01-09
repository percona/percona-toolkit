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
# AdvisorRules package
# ###########################################################################
{
# Package: AdvisorRules
# AdvisorRules is a parent class for advisor rule modules like
# <QueryAdivsorRules>.
package AdvisorRules;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(PodParser) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      rules     => [],
      rule_info => {},
   };
   return bless $self, $class;
}

# Arguments:
#   * file     scalar: file name with POD to parse rules from
#   * section  scalar: section name for rule items, should be RULES
#   * rules    arrayref: optional list of rules to load info for
# Parses rules from the POD section/subsection in file, adding rule
# info found therein to %rule_info.  Then checks that rule info
# was gotten for all the required rules.
sub load_rule_info {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(file section ) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $rules = $args{rules} || $self->{rules};
   my $p     = $self->{PodParser};

   # Parse rules and their info from the file's POD, saving
   # values to %rule_info.
   $p->parse_from_file($args{file});
   my $rule_items = $p->get_items($args{section});
   my %seen;
   foreach my $rule_id ( keys %$rule_items ) {
      my $rule = $rule_items->{$rule_id};
      die "Rule $rule_id has no description" unless $rule->{desc};
      die "Rule $rule_id has no severity"    unless $rule->{severity};
      die "Rule $rule_id is already defined"
         if exists $self->{rule_info}->{$rule_id};
      $self->{rule_info}->{$rule_id} = {
         id          => $rule_id,
         severity    => $rule->{severity},
         description => $rule->{desc},
      };
   }

   # Check that rule info was gotten for each requested rule.
   foreach my $rule ( @$rules ) {
      die "There is no info for rule $rule->{id} in $args{file}"
         unless $self->{rule_info}->{ $rule->{id} };
   }

   return;
}

sub get_rule_info {
   my ( $self, $id ) = @_;
   return unless $id;
   return $self->{rule_info}->{$id};
}

# Used for testing.
sub _reset_rule_info {
   my ( $self ) = @_;
   $self->{rule_info} = {};
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
# End AdvisorRules package
# ###########################################################################
