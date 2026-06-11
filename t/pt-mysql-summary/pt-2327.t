#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use PerconaTest;
use Sandbox;
use DSNParser;
require VersionParser;
use Test::More;

local $ENV{PTDEBUG} = "";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');
my $cnf = '/tmp/12345/my.sandbox.cnf';
my $output;

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
else {
   plan tests => 5;
}

$sb->do_as_root("source", q/create user pt2302 identified by "root_'f<=*password"/);
$sb->do_as_root("source", q/grant all on *.* to pt2302/);

my $cmd = "$trunk/bin/pt-mysql-summary --sleep 1 -- --defaults-file=$cnf --user=pt2302 --password=\"root_'f<=*password\"";

$output = `$cmd 2>&1`;

unlike(
   $output,
   qr/eval: Syntax error: Unterminated quoted string/s,
   "pt-mysql-summary does not stop with password containing an apostrophe"
);

unlike(
   $output,
   qr/Access denied for user/s,
   "pt-mysql-summary works fine with password containing an apostrophe"
);

$sb->do_as_root("source", q/drop user pt2302/);
$sb->do_as_root("source", q/create user pt2302 identified by 'root_"f<=*password'/);
$sb->do_as_root("source", q/grant all on *.* to pt2302/);

$cmd = "$trunk/bin/pt-mysql-summary --sleep 1 -- --defaults-file=$cnf --user=pt2302 --password='root_\"f<=*password'";

$output = `$cmd 2>&1`;

unlike(
   $output,
   qr/eval: Syntax error: Unterminated quoted string/s,
   "pt-mysql-summary does not stop with password containing a quote"
);

unlike(
   $output,
   qr/Access denied for user/s,
   "pt-mysql-summary works fine with password containing a quote"
);
# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root("source", q/drop user pt2302/);
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
