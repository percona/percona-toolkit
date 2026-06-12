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
use SqlModes;
use VersionParser;
require "$trunk/bin/pt-show-grants";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

if ( VersionParser->new($dbh) lt '8.0.17') {
   plan skip_all => "This test requires MySQL 8.0.17 or higher";
}

$sb->wipe_clean($dbh);

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';

diag(`/tmp/12345/use -u root -e "CREATE USER 'sally'\@'%' IDENTIFIED WITH 'caching_sha2_password' BY 'A005?>6LZe1'"`);

ok(
   `/tmp/12345/use -s -u sally -p'A005?>6LZe1' -e "SELECT 1" 2>/dev/null`,
   'User sally can log in before tests'
);

$output = output(
   sub { pt_show_grants::main('-F', $cnf, qw(--only sally)); }
);

like(
   $output,
   qr/0x24412430303524/,
   'Password printed in HEX'
) or diag($output);

diag(`/tmp/12345/use -u root -e "DROP USER 'sally'\@'%'"`);
open(my $pipe, '|-', '/tmp/12345/use -u root');
print $pipe $output;
close($pipe);

ok(
   `/tmp/12345/use -s -u sally -p'A005?>6LZe1' -e "SELECT 1" 2>/dev/null`,
   'User sally can log in'
) or diag($output);

diag(`/tmp/12345/use -u root -e "DROP USER 'sally'\@'%'"`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
