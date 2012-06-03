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
require "$trunk/bin/pt-upgrade";

# This runs immediately if the server is already running, else it starts it.
diag(`$trunk/sandbox/start-sandbox master 12347 >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');
my $dbh2 = $sb->get_dbh_for('slave2');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to second sandbox master';
}
else {
   plan tests => 2;
}

$sb->load_file('master', 't/pt-upgrade/samples/001/tables.sql');
$sb->load_file('slave2', 't/pt-upgrade/samples/001/tables.sql');

my $cmd = "$trunk/bin/pt-upgrade h=127.1,P=12345,u=msandbox,p=msandbox P=12347 --compare results,warnings --zero-query-times";

# Test that non-SELECT queries are skipped by default.
ok(
   no_diff(
      "$cmd $trunk/t/pt-upgrade/samples/001/non-selects.log",
      't/pt-upgrade/samples/001/non-selects.txt'
   ),
   'Non-SELECT are skipped by default'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
$sb->wipe_clean($dbh2);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
