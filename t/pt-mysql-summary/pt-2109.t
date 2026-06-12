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
my $has_keyring_plugin;

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
else {
   plan tests => 3;
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';

my ($orig_sql_mode) = $dbh->selectrow_array(q{SELECT @@SQL_MODE});
$dbh->do("SET GLOBAL SQL_MODE='ANSI_QUOTES'");

my $cmd = "$trunk/bin/pt-mysql-summary --sleep 1 -- --defaults-file=$cnf";

$output = `$cmd 2>&1`;

unlike(
   $output,
   qr/Unknown column 'keyring%' in 'where clause'/s,
   "pt-mysql-summary works fine with SQL Mode ANSI_QUOTES"
);

unlike(
   $output,
   qr/You have an error in your SQL syntax.*wsrep_on/s,
   "pt-mysql-summary works fine with PXC and SQL Mode ANSI_QUOTES"
);

# #############################################################################
# Done.
# #############################################################################
$dbh->do("SET GLOBAL SQL_MODE='${orig_sql_mode}'");
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
