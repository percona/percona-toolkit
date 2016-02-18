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

require "$trunk/bin/pt-show-grants";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

$sb->wipe_clean($dbh);

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';

# #############################################################################
# Issue 551: mk-show-grants does not support listing all grants for a single
# user (over multiple hosts)
# #############################################################################

# to make creating users easier we remove NO_AUTO_CREATE_USER mode
my $modes = new SqlModes($dbh, global=>1);
$modes->del('NO_AUTO_CREATE_USER');
diag(`/tmp/12345/use -u root -e "GRANT USAGE ON *.* TO 'bob'\@'%'"`);
diag(`/tmp/12345/use -u root -e "GRANT USAGE ON *.* TO 'bob'\@'localhost'"`);
diag(`/tmp/12345/use -u root -e "GRANT USAGE ON *.* TO 'bob'\@'192.168.1.1'"`);
$modes->restore_original_modes;

$output = output(
   sub { pt_show_grants::main('-F', $cnf, qw(--only bob --no-header)); }
);

my $expected_57 = <<'END_OUTPUT_1';
-- Grants for 'bob'@'%'
CREATE USER IF NOT EXISTS 'bob'@'%';
ALTER USER 'bob'@'%' IDENTIFIED WITH 'mysql_native_password' REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK;
GRANT USAGE ON *.* TO 'bob'@'%';
-- Grants for 'bob'@'192.168.1.1'
CREATE USER IF NOT EXISTS 'bob'@'192.168.1.1';
ALTER USER 'bob'@'192.168.1.1' IDENTIFIED WITH 'mysql_native_password' REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK;
GRANT USAGE ON *.* TO 'bob'@'192.168.1.1';
-- Grants for 'bob'@'localhost'
CREATE USER IF NOT EXISTS 'bob'@'localhost';
ALTER USER 'bob'@'localhost' IDENTIFIED WITH 'mysql_native_password' REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK;
GRANT USAGE ON *.* TO 'bob'@'localhost';
END_OUTPUT_1

my $expected_56 = <<'END_OUTPUT_2';
-- Grants for 'bob'@'%'
GRANT USAGE ON *.* TO 'bob'@'%';
-- Grants for 'bob'@'192.168.1.1'
GRANT USAGE ON *.* TO 'bob'@'192.168.1.1';
-- Grants for 'bob'@'localhost'
GRANT USAGE ON *.* TO 'bob'@'localhost';
END_OUTPUT_2

my $expected = $sandbox_version < '5.7' ? $expected_56 : $expected_57;

is(
   $output,
   $expected,
   '--only user gets grants for user on all hosts (issue 551)'
);

$output = output(
   sub { pt_show_grants::main('-F', $cnf, qw(--only bob@192.168.1.1 --no-header)); }
);

$expected_57 = <<'END_OUTPUT_3';
-- Grants for 'bob'@'192.168.1.1'
CREATE USER IF NOT EXISTS 'bob'@'192.168.1.1';
ALTER USER 'bob'@'192.168.1.1' IDENTIFIED WITH 'mysql_native_password' REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK;
GRANT USAGE ON *.* TO 'bob'@'192.168.1.1';
END_OUTPUT_3

$expected_56 = <<'END_OUTPUT_4';
-- Grants for 'bob'@'192.168.1.1'
GRANT USAGE ON *.* TO 'bob'@'192.168.1.1';
END_OUTPUT_4

$expected = $sandbox_version < '5.7' ? $expected_56 : $expected_57;

is(
   $output,
   $expected,
   '--only user@host'
);


diag(`/tmp/12345/use -u root -e "DROP USER 'bob'\@'%'"`);
diag(`/tmp/12345/use -u root -e "DROP USER 'bob'\@'localhost'"`);
diag(`/tmp/12345/use -u root -e "DROP USER 'bob'\@'192.168.1.1'"`);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
