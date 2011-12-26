#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 5;

use PerconaTest;
use QueryAdvisorRules;
use Advisor;
use PodParser;

# This module's purpose is to run rules and return a list of the IDs of the
# triggered rules.  It should be very simple.  (But we don't want to put the two
# modules together.  Their purposes are distinct.)
my $p   = PodParser->new();
my $qar = QueryAdvisorRules->new(PodParser => $p);
my $adv = Advisor->new(match_type=>"pos");

# This should make $qa internally call get_rules() on $qar and save the rules
# into its own list.  If the user plugs in his own module, we'd call
# load_rules() on that too, and just append the rules (with checks that they
# don't redefine any rule IDs).
$adv->load_rules($qar);

# To test the above, we ask it to load the same rules twice.  It should die with
# an error like "Rule LIT.001 already exists, and cannot be redefined"
throws_ok (
   sub { $adv->load_rules($qar) },
   qr/Rule \S+ already exists and cannot be redefined/,
   'Duplicate rules are caught',
);

# We'll also load the rule info, so we can test $adv->get_rule_info() after the
# POD is loaded.
$qar->load_rule_info(
   rules   => [ $qar->get_rules() ],
   file    => "$trunk/bin/pt-query-advisor",
   section => 'RULES',
);

# This should make $qa call $qar->get_rule_info('....') for every rule ID it
# has, and store the info, and make sure that nothing is redefined.  A user
# shouldn't be able to load a plugin that redefines the severity/desc of a
# built-in rule.  Maybe we'll provide a way to override that, though by default
# we want to warn and be strict.
$adv->load_rule_info($qar);

# TODO: write a test that the rules are described as defined in the POD of the
# tool.  Testing one rule should be enough.

# Test that it can't be redefined...
throws_ok (
   sub { $adv->load_rule_info($qar) },
   qr/Info for rule \S+ already exists and cannot be redefined/,
   'Duplicate rule info is caught',
);

is_deeply(
   $adv->get_rule_info('ALI.001'),
   {
      id          => 'ALI.001',
      severity    => 'note',
      description => 'Aliasing without the AS keyword.  Explicitly using the AS keyword in column or table aliases, such as "tbl AS alias," is more readable than implicit aliases such as "tbl alias".',
   },
   'get_rule_info()'
);


# #############################################################################
# Ignore rules.
# #############################################################################
$adv = Advisor->new(
   match_type   => "pos",
   ignore_rules => { 'LIT.002' => 1 },
);
$adv->load_rules($qar);
$adv->load_rule_info($qar);
is(
   $adv->get_rule_info('LIT.002'),
   undef,
   "Didn't load ignored rule"
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $p->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
