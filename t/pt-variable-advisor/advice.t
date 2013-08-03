#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-variable-advisor";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
my $dsn = $sb->dsn_for('master');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1168106
# pt-variable-advisor has the wrong default value for
# innodb_max_dirty_pages_pct in 5.6.10
# #############################################################################

my @args   = "$dsn";
my $output = "";

$output = output(
   sub { pt_variable_advisor::main(@args) },
);

unlike(
   $output,
   qr/innodb_max_dirty_pages_pct/,
   "No innodb_max_dirty_pages_pct warning (bug 1168106)"
);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
