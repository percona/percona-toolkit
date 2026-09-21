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

my $dp  = new DSNParser(opts => $dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');
my $cnf = '/tmp/12345/my.sandbox.cnf';

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

my $role_name = 'ptms_role_test';
my $user_name = 'ptms_role_user';
my $user_host = '%';

my $roles_supported = eval {
   $dbh->do("DROP USER IF EXISTS '$user_name'\@'$user_host'");
   $dbh->do("DROP ROLE IF EXISTS $role_name");
   $dbh->do("CREATE ROLE $role_name");
   $dbh->do("CREATE USER '$user_name'\@'$user_host' IDENTIFIED BY 'ptms_role_user_pwd'");
   $dbh->do("GRANT $role_name TO '$user_name'\@'$user_host'");
   1;
};

if ( !$roles_supported ) {
   my $err = $EVAL_ERROR || 'roles are not supported on this server';
   plan skip_all => "Cannot test roles: $err";
}

my $cmd = "$trunk/bin/pt-mysql-summary --sleep 1 -- --defaults-file=$cnf";
my $out = `$cmd 2>&1`;

like(
   $out,
   qr/\bRoles\b/s,
   'Roles section is present in pt-mysql-summary output'
) or diag($out);

like(
   $out,
   qr/Role Name:\s*$role_name/s,
   'Created role is reported by pt-mysql-summary'
) or diag($out);

like(
   $out,
   qr/Active:\s*1/s,
   'Role active state is reported by pt-mysql-summary'
) or diag($out);

# #############################################################################
# Done.
# #############################################################################


$dbh->do("DROP USER IF EXISTS '$user_name'\@'$user_host'");
$dbh->do("DROP ROLE IF EXISTS $role_name");

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
