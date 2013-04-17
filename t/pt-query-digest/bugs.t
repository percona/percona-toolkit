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

use Sandbox;
use PerconaTest;

require "$trunk/bin/pt-query-digest";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $output  = '';
my $exit_status;
my $cnf     = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my $samples = "$trunk/t/pt-query-digest/samples";

# #############################################################################
# pt-query-digest with custom --group-by throws error
# https://bugs.launchpad.net/percona-toolkit/+bug/957442
# #############################################################################

$output = output(sub {
   $exit_status = pt_query_digest::main('--group-by=page',
         '--filter', "$samples/bug_957442_filter.pl",
         "$samples/bug_957442_sample.log")
});

ok(
   !$exit_status,
   "Bug 957442: No error with a custom --filter & --group-by=page"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
