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
require "$trunk/bin/pt-deadlock-logger";

my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-deadlock-logger -F $cnf h=127.1";

$sb->wipe_clean($dbh1);
$sb->create_dbs($dbh1, ['test']);

# #############################################################################
# Issue 386: Make mk-deadlock-logger auto-create the --dest table
# #############################################################################
is_deeply(
   $dbh1->selectall_arrayref('show tables from `test` like "issue_386"'),
   [],
   'Deadlocks table does not exit (issue 386)'
);

`$cmd --dest D=test,t=issue_386 --run-time 1s --interval 1s --create-dest-table`;

is_deeply(
   $dbh1->selectall_arrayref('show tables from `test` like "issue_386"'),
   [['issue_386']],
   'Deadlocks table created with --create-dest-table (issue 386)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
exit;
