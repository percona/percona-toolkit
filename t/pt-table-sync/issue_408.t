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

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

diag(`$trunk/sandbox/start-sandbox master 12347 >/dev/null`);
my $dbh2 = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to second sandbox master';
}
else {
   plan tests => 1;
}

$sb->wipe_clean($master_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# Need at least 1 table so the db will be used.
$master_dbh->do('create table test.foo (i int)');

# #############################################################################
# Issue 408: DBD::mysql::st execute failed: Unknown database 'd1' at
# ./mk-table-sync line 2015.
# #############################################################################

$output = `$trunk/bin/pt-table-sync --databases test --execute h=127.1,P=12345,u=msandbox,p=msandbox h=127.1,P=12347 2>&1`;
like(
   $output,
   qr/Unknown database 'test'/,
   'Warn about --databases missing on dest host'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
diag(`/tmp/12347/stop >/dev/null`);
diag(`rm -rf /tmp/12347 >/dev/null`);
exit;
