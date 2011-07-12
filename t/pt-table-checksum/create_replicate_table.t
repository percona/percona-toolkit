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
my $vp = new VersionParser();
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
   plan tests => 5;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf 127.0.0.1";

$sb->wipe_clean($master_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 77: mk-table-checksum should be able to create the --replicate table
# #############################################################################

is_deeply(
   $master_dbh->selectall_arrayref('show tables from test'),
   [],
   "Checksum table does not exist on master"
);

is_deeply(
   $slave_dbh->selectall_arrayref('show tables from test'),
   [],
   "Checksum table does not exist on slave"
);

# First check that, like a Klingon, it dies with honor.
$output = `$cmd --replicate test.checksum 2>&1`;
like(
   $output,
   qr/replicate table .+ does not exist/,
   'Dies with honor when replication table does not exist'
);

output(
   sub { pt_table_checksum::main('-F', $cnf,
      qw(--create-replicate-table --replicate test.checksum 127.1)) },
   stderr => 0,
);

# In 5.0 "on" in "on update" is lowercase, in 5.1 it's uppercase.
my $create_tbl = lc("CREATE TABLE `checksum` (
  `db` char(64) NOT NULL,
  `tbl` char(64) NOT NULL,
  `chunk` int(11) NOT NULL,
  `boundaries` char(100) NOT NULL,
  `this_crc` char(40) NOT NULL,
  `this_cnt` int(11) NOT NULL,
  `master_crc` char(40) default NULL,
  `master_cnt` int(11) default NULL,
  `ts` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`db`,`tbl`,`chunk`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1");

# In 5.0 there's 2 spaces, in 5.1 there 1.
if ( $vp->version_ge($master_dbh, '5.1.0') ) {
   $create_tbl =~ s/primary key  /primary key /;
}

is(
   lc($master_dbh->selectrow_hashref('show create table test.checksum')->{'create table'}),
   $create_tbl,
   'Creates the replicate table'
);

# ############################################################################
# Issue 1318: mk-tabke-checksum --create-replicate-table doesn't replicate
# ############################################################################
is(
   lc($slave_dbh->selectrow_hashref('show create table test.checksum')->{'create table'}),
   $create_tbl,
   'Creates the replicate table replicates (issue 1318)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
