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
require "$trunk/bin/pt-deadlock-logger";

my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-deadlock-logger -F $cnf h=127.1";

$sb->wipe_clean($dbh1);
$sb->create_dbs($dbh1, ['test']);

# #############################################################################
# Test --clear-deadlocks
# #############################################################################

# The clear-deadlocks table comes and goes quickly so we can really
# only search the debug output for evidence that it was created.
$output = `PTDEBUG=1 $trunk/bin/pt-deadlock-logger F=$cnf,D=test --clear-deadlocks test.make_deadlock --iterations 1 2>&1`;
like(
   $output,
   qr/INSERT INTO test.make_deadlock/,
   'Create --clear-deadlocks table (output)'
);
like(
   $output,
   qr/CREATE TABLE test.make_deadlock/,
   'Create --clear-deadlocks table (debug)'
);


# #############################################################################
# Issue 942: mk-deadlock-logger --clear-deadlocks doesn't work with --interval
# #############################################################################
$output = `PTDEBUG=1 $trunk/bin/pt-deadlock-logger F=$cnf,D=test --clear-deadlocks test.make_deadlock2 --interval 1 --run-time 1 2>&1`;
like(
   $output,
   qr/CREATE TABLE test.make_deadlock2/,
   '--clear-deadlocks with --interval (isue 942)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
