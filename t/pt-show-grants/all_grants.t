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
diag(`/tmp/12345/use -u root -e "GRANT USAGE ON *.* TO 'bob'\@'%'"`);
diag(`/tmp/12345/use -u root -e "GRANT USAGE ON *.* TO 'bob'\@'localhost'"`);
diag(`/tmp/12345/use -u root -e "GRANT USAGE ON *.* TO 'bob'\@'192.168.1.1'"`);

$output = output(
   sub { pt_show_grants::main('-F', $cnf, qw(--only bob --no-header)); }
);
is(
   $output,
"-- Grants for 'bob'\@'%'
GRANT USAGE ON *.* TO 'bob'\@'%';
-- Grants for 'bob'\@'192.168.1.1'
GRANT USAGE ON *.* TO 'bob'\@'192.168.1.1';
-- Grants for 'bob'\@'localhost'
GRANT USAGE ON *.* TO 'bob'\@'localhost';
",
   '--only user gets grants for user on all hosts (issue 551)'
);

$output = output(
   sub { pt_show_grants::main('-F', $cnf, qw(--only bob@192.168.1.1 --no-header)); }
);
is(
   $output,
"-- Grants for 'bob'\@'192.168.1.1'
GRANT USAGE ON *.* TO 'bob'\@'192.168.1.1';
",
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
