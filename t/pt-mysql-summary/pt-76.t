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
use File::Temp qw( tempdir );

local $ENV{PTDEBUG} = "";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox';
}
else {
   plan tests => 5;
}

my ($tool) = 'pt-mysql-summary';

$dbh->do("DROP USER IF EXISTS `pt-76`");
$dbh->do("CREATE USER `pt-76` IDENTIFIED BY 'foo&bar'");

my $out = `$trunk/bin/$tool --config $trunk/t/pt-mysql-summary/samples/pt-mysql-summary.conf.001 2>/dev/null -- --defaults-file=/tmp/12345/my.sandbox.cnf`;

like(
   $out,
   qr/User | pt-76/,
   "Password with & character works"
);

$out = `$trunk/bin/$tool --config $trunk/t/pt-mysql-summary/samples/pt-mysql-summary.conf.003 2>/dev/null -- --defaults-file=/tmp/12345/my.sandbox.cnf`;

like(
   $out,
   qr/User | pt-76/,
   "Password with & character and inline comment works"
);

$dbh->do("ALTER USER `pt-76` IDENTIFIED BY 'foo#bar'");

$out = `$trunk/bin/$tool --config $trunk/t/pt-mysql-summary/samples/pt-mysql-summary.conf.002 2>/dev/null -- --defaults-file=/tmp/12345/my.sandbox.cnf`;

like(
   $out,
   qr/User | pt-76/,
   "Password with # character works"
);

$out = `$trunk/bin/$tool --config $trunk/t/pt-mysql-summary/samples/pt-mysql-summary.conf.004 2>/dev/null -- --defaults-file=/tmp/12345/my.sandbox.cnf`;

like(
   $out,
   qr/User | pt-76/,
   "Password with # character and inline comment works"
);

# #############################################################################
# Done.
# #############################################################################
$dbh->do("DROP USER IF EXISTS `pt-76`");
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
