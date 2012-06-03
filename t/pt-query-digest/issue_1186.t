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
use DSNParser;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

# #############################################################################
# Issue 1186: mk-query-digest --processlist --interval --filter ignores interval
# #############################################################################

my $output = `PTDEBUG=1 $trunk/bin/pt-query-digest --processlist h=127.1,P=12345,u=msandbox,p=msandbox --run-time 2 --port 12345 --interval .5 2>&1`;

my @times = $output =~ m/Current time: \S+/g;
ok(
   @times > 4 && @times <= 7,
   "--interval limits number of processlist polls (issue 1186)"
);

$output = `PTDEBUG=1 $trunk/bin/pt-query-digest --processlist h=127.1,P=12345,u=msandbox,p=msandbox --run-time 2 --port 12345 --interval .5 --filter '(\$event->{arg} =~ /NEVER HAPPEN/)' 2>&1`;

@times = $output =~ m/Current time: \S+/g;
ok(
   @times > 4 && @times <= 7,
   "--filter doesn't bypass --interval (issue 1186)"
);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
