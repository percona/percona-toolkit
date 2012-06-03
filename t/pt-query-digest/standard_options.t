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
   plan tests => 2;
}

my $output;

# #############################################################################
# Issue 248: Add --user, --pass, --host, etc to all tools
# #############################################################################

# This is a poor test because sometimes it will catch queries on the proclist
# and other times it won't.
$output = `$trunk/bin/pt-query-digest --processlist 127.1,P=12345,u=msandbox,p=msandbox --run-time 1 --port 12345`;
like(
   $output,
   qr/(?:Rank\s+Query ID|No events processed)/,
   'DSN opts inherit from --host, --port, etc. (issue 248)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
