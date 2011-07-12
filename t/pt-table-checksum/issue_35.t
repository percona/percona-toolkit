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
require "$trunk/bin/pt-table-checksum";

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
   plan tests => 3;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.0.0.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/before.sql');

# #############################################################################
# Issue 35: mk-table-checksum dies when one server is missing a table
# #############################################################################

diag(`/tmp/12345/use -e 'SET SQL_LOG_BIN=0; CREATE TABLE test.only_on_master(a int);'`);

$output = `$cmd P=12346 -t test.only_on_master 2>&1`;
like($output, qr/MyISAM\s+NULL\s+0/, 'Table on master checksummed');
like($output, qr/MyISAM\s+NULL\s+NULL/, 'Missing table on slave checksummed');
like(
   $output,
   qr/test\.only_on_master does not exist on slave 127.0.0.1:12346/,
   'Warns about missing slave table'
);

diag(`/tmp/12345/use -e 'SET SQL_LOG_BIN=0; DROP TABLE test.only_on_master;'`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
