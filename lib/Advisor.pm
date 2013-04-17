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
# Advisor package
# ###########################################################################
{
# Package: Advisor
# Advisor loads, checks, and runs rules for the various mk-*-advisor tools.
package Advisor;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

# Sub: new
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   match_type   - How rules match: "bool" or "pos"
#   ignore_rules - Hashref with rule IDs to ignore
#
# Returns:
#   Advisor object
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(match_type) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
      %args,
      rules          => [],  # Rules from all advisor modules.
      rule_index_for => {},  # Maps rules by ID to their array index in $rules.
      rule_info      => {},  # ID, severity, description, etc. for each rule.
   };

   return bless $self, $class;
}

# Sub: load_rules
#   Load rules from the given advisor module.  Will die on duplicate
#   rule IDs.
#
# Parameters:
#   $advisor - An *AdvisorRules module, like <QueryAdvisorRules>
sub load_rules {
   my ( $self, $advisor ) = @_;
   return unless $advisor;
   PTDEBUG && _d('Loading rules from', ref $advisor);

   # Starting index value in rules arrayref for these rules.
   # This is >0 if rules from other advisor modules have
   # already been loaded.
   my $i = scalar @{$self->{rules}};

   RULE:
   foreach my $rule ( $advisor->get_rules() ) {
      my $id = $rule->{id};
      if ( $self->{ignore_rules}->{"$id"} ) {
         PTDEBUG && _d("Ignoring rule", $id);
         next RULE;
      }
      die "Rule $id already exists and cannot be redefined"
         if defined $self->{rule_index_for}->{$id};
      push @{$self->{rules}}, $rule;
      $self->{rule_index_for}->{$id} = $i++;
   }

   return;
}

# Sub: load_rule_info
#   Load rule information (severity and description) from the given advisor
#   module.
#
# Parameters:
#   $advisor - An *AdvisorRules module, like <QueryAdvisorRules>
sub load_rule_info {
   my ( $self, $advisor ) = @_;
   return unless $advisor;
   PTDEBUG && _d('Loading rule info from', ref $advisor);
   my $rules = $self->{rules};
   foreach my $rule ( @$rules ) {
      my $id = $rule->{id};
      if ( $self->{ignore_rules}->{"$id"} ) {
         # This shouldn't happen.  load_rules() should keep any ignored
         # rules out of $self->{rules}.
         die "Rule $id was loaded but should be ignored";
      }
      my $rule_info = $advisor->get_rule_info($id);
      next unless $rule_info;
      die "Info for rule $id already exists and cannot be redefined"
         if $self->{rule_info}->{$id};
      $self->{rule_info}->{$id} = $rule_info;
   }
   return;
}


# Sub: run_rules
#   Run all rules from all advisors loaded ealier.
#
# Parameters:
#   %args - Arguments passed through to each rule's coderef
#
# Returns:
#   An arrayref of rule IDs that matched and arrayref of pos
#   where those rules matched (if <new()> match_type is "bool").
sub run_rules {
   my ( $self, %args ) = @_;
   my @matched_rules;
   my @matched_pos;
   my $rules      = $self->{rules};
   my $match_type = lc $self->{match_type};
   foreach my $rule ( @$rules ) {
      eval {
         my $match = $rule->{code}->(%args);
         if ( $match_type eq 'pos' ) {
            if ( defined $match ) {
               PTDEBUG && _d('Matches rule', $rule->{id}, 'near pos', $match);
               push @matched_rules, $rule->{id};
               push @matched_pos,   $match;
            }
         }
         elsif ( $match_type eq 'bool' ) {
            if ( $match ) {
               PTDEBUG && _d("Matches rule", $rule->{id});
               push @matched_rules, $rule->{id};
            }
         }
      };
      if ( $EVAL_ERROR ) {
         warn "Code for rule $rule->{id} caused an error: $EVAL_ERROR";
      }
   }
   return \@matched_rules, \@matched_pos;
};


# Sub: get_rule_info
#   Get the information for a rule by ID.
#
# Parameters:
#   $id - Rule ID
#
# Returns:
#   Hashref with the rule's information (id, severity, description)
sub get_rule_info {
   my ( $self, $id ) = @_;
   return unless $id;
   return $self->{rule_info}->{$id};
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
# End Advisor package
# ###########################################################################
