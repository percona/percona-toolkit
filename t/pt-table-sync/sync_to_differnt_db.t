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
require "$trunk/bin/pt-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

diag(`$trunk/sandbox/start-sandbox master 12348 >/dev/null`);
my $dbh2 = $sb->get_dbh_for('master1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to second sandbox master';
}
else {
   plan tests => 3;
}

$sb->wipe_clean($master_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-sync/samples/before.sql');

# #############################################################################
# Issue 40: mk-table-sync feature: sync to different db
# #############################################################################

$dbh2->do('DROP DATABASE IF EXISTS d2');
$dbh2->do('CREATE DATABASE d2');
$dbh2->do('CREATE TABLE d2.test2 (a INT NOT NULL, b char(2) NOT NULL, PRIMARY KEY  (`a`,`b`) )');

$output = `$trunk/bin/pt-table-sync --no-check-slave --execute h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=test1  h=127.1,P=12348,D=d2,t=test2 2>&1`;
is(
   $output,
   '',
   'Sync to different db.tbl (issue 40)'
);

$output     = `/tmp/12345/use -e 'SELECT * FROM test.test1'`;
my $output2 = `/tmp/12348/use -e 'SELECT * FROM d2.test2'`;
is(
   $output,
   $output2,
   'Original db.tbl matches different db.tbl (issue 40)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
