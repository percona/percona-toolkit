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
use Data::Dumper;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-archiver";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

$sb->create_dbs($master_dbh, ['test']);
$sb->load_file('master', 't/pt-archiver/samples/tables1-4.sql');

# ###########################################################################
# pt-archiver deletes data despite --dry-run
# https://bugs.launchpad.net/percona-toolkit/+bug/1199589
# ###########################################################################

my $rows_before = $master_dbh->selectall_arrayref("SELECT * FROM test.table_1 ORDER BY a");

$output = `$cmd --optimize --dry-run --purge --where 1=1 --source D=test,t=table_1,F=$cnf 2>&1`;

my $rows_after = $master_dbh->selectall_arrayref("SELECT * FROM test.table_1 ORDER BY a");

is_deeply(
   $rows_after,
   $rows_before,
   "--optimize does not consume --dry-run (bug 1199589)"
) or diag(Dumper($rows_after));

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
