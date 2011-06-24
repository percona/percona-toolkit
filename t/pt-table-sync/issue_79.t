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
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 6;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-sync/samples/before.sql');
$sb->load_file('master', 't/pt-table-sync/samples/checksum_tbl.sql');

# #############################################################################
# Issue 79: mk-table-sync with --replicate doesn't honor --tables
# #############################################################################

$master_dbh->do('create table test.messages (i int)');
sleep 1;
$slave_dbh->do('insert into test.messages values (1), (2), (3)');

# The previous test should have left test.messages on the slave (12346)
# out of sync. Now we also unsync test2 on the slave and then re-sync only
# it. If --tables is honored, only test2 on the slave will be synced.
$sb->use('master', "-D test -e \"SET SQL_LOG_BIN=0; INSERT INTO test2 VALUES (1,'a'),(2,'b')\"");
diag(`$trunk/bin/pt-table-checksum --replicate=test.checksum h=127.1,P=12345,u=msandbox,p=msandbox -d test > /dev/null`);

is_deeply(
   $master_dbh->selectall_arrayref('select * from test.messages'),
   [],
   'test.messages on master empty'
);
is_deeply(
   $slave_dbh->selectall_arrayref('select * from test.messages'),
   [[1],[2],[3]],
   'test.messages on slave has values'
);

# Test that what the doc says about --tables is true:
# "Table names may be qualified with the database name."
# In the code, a qualified db.tbl name is used.
# So we'll test first an unqualified tbl name.
$output = `$trunk/bin/pt-table-sync h=127.1,P=12345,u=msandbox,p=msandbox --replicate test.checksum --execute -d test -t test2 -v`;
unlike($output, qr/messages/, '--replicate honors --tables (1/4)');
like($output,   qr/test2/,    '--replicate honors --tables (2/4)');

# Now we'll test with a qualified db.tbl name.
$sb->use('slave1', '-D test -e "TRUNCATE TABLE test2; TRUNCATE TABLE messages"');
diag(`$trunk/bin/pt-table-checksum --replicate=test.checksum h=127.1,P=12345,u=msandbox,p=msandbox -d test > /dev/null`);

$output = `$trunk/bin/pt-table-sync h=127.1,P=12345,u=msandbox,p=msandbox --replicate test.checksum --execute -d test -t test.test2 -v`;
unlike($output, qr/messages/, '--replicate honors --tables (3/4)');
like($output,   qr/test2/,    '--replicate honors --tables (4/4)');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
