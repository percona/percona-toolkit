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
} elsif ($sandbox_version < '8.0') {
    plan skip_all => "There are no roles in this MySQL version. Need MySQL 8.0+";
} else {
   plan tests => 49;
}

$sb->wipe_clean($dbh);

my $setup_queries = [
    "CREATE ROLE IF NOT EXISTS 'app_developer', 'app_read', 'app_write', 'tester';",
    "GRANT ALL ON test.* TO 'app_developer';",
    "GRANT SELECT ON test.* TO 'app_read';",
    "GRANT SELECT ON test.* TO 'tester';",
    "CREATE USER 'zapp'\@'localhost' IDENTIFIED WITH 'mysql_native_password' BY 'test1234';",
    "GRANT 'app_read','app_write' TO 'zapp'\@'localhost';",
    "GRANT 'tester' TO 'zapp'\@'localhost' WITH ADMIN OPTION;",
    "FLUSH PRIVILEGES",
];

my $cleanup_queries = [
    "DROP USER IF EXISTS 'zapp'\@'localhost'",
    "DROP ROLE IF EXISTS 'app_developer', 'app_read', 'app_write', 'tester'",
    "FLUSH PRIVILEGES",
];
for my $query(@$setup_queries) {
    $sb->do_as_root('master', $query);
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';

eval {
   $output = output(
      sub { pt_show_grants::main('-F', $cnf, '--skip-unused-roles'); }
   );
};
is(
   $EVAL_ERROR,
   '',
   'Does not die on anonymous user (issue 445)',
);

like(
   $output,
   qr/CREATE ROLE IF NOT EXISTS `app_read`;/,
   'Roles has been created'
) or diag($output);

unlike(
   $output,
   qr/CREATE ROLE IF NOT EXISTS `app_developer`;/,
   'Unused roles has been skipped'

);

## Do a cleanup and try to run all the queries from the output
for my $query(@$cleanup_queries) {
    $sb->do_as_root('master', $query);
}

my @lines = split(/\n/, $output);
my $count=0;

for my $query(@lines) {                       
    next if $query =~ m/^-- /;
    $count++;
    eval { $sb->do_as_root('master', $query) };
    is(
        $EVAL_ERROR,
        '',
        "Ran query $count from the output of pt-show grants",
    ) or diag("Cannot execute query from the output: $query -> $EVAL_ERROR");
}

## Cleanup to leave sandbox ready for next test file.
for my $query(@$cleanup_queries) {
    $sb->do_as_root('master', $query);
}

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
