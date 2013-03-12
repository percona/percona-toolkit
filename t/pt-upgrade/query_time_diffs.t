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
use File::Basename;

$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1; 
$ENV{PRETTY_RESULTS} = 1; 

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-upgrade";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('host1');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox host1'; 
}

my $host1_dsn   = $sb->dsn_for('host1');
my $samples     = "$trunk/t/pt-upgrade/samples";
my $exit_status = 0;
my $output;

$output = output(
   sub {
      $exit_status = pt_upgrade::main($host1_dsn, "$samples/res001")
   },
   stderr => 1,
);

is(
   $exit_status,
   4,
   "Query time diff: exit 4"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
