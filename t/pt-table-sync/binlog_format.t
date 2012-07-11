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
elsif ( VersionParser->new($master_dbh) < '5.1.5' ) {
      plan skip_all => 'Requires MySQL 5.1.5 or newer';
}
else {
   plan tests => 7;
}

# #############################################################################
# Issue 95: Make mk-table-sync force statement-based binlog format on 5.1
# #############################################################################

$sb->create_dbs($master_dbh, ['test']);
$master_dbh->do('create table test.t (i int, unique index (i))');
$master_dbh->do('insert into test.t values (1),(2)');
$sb->wait_for_slaves();
$slave_dbh->do('insert into test.t values (3)');  # only on the slaves

is_deeply(
   $master_dbh->selectall_arrayref('select * from test.t order by i'),
   [[1],[2]],
   'Data on master before sync'
);

# Slaves have an extra row, something to sync.
my $rows = $slave_dbh->selectall_arrayref('select * from test.t order by i');
is_deeply(
   $rows,
   [[1],[2],[3]],
   'Data on slave before sync'
) or print Dumper($rows);

$master_dbh->do("SET GLOBAL binlog_format='ROW'");
$master_dbh->disconnect();
$master_dbh = $sb->get_dbh_for('master');

is_deeply(
   $master_dbh->selectrow_arrayref('select @@binlog_format'),
   ['ROW'],
   'Set global binlog_format = ROW'
);

is(
   output(
      sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
         qw(--sync-to-master -t test.t --print --execute)) },
      trf => \&remove_traces,
   ),
   "DELETE FROM `test`.`t` WHERE `i`='3' LIMIT 1;
",
   "Executed DELETE"
);

wait_until(
   sub {
      my $rows = $slave_dbh->selectall_arrayref('select * from test.t');
      return $rows && @$rows == 2;
   }
) or die "DELETE did not replicate to slave";

is_deeply(
   $slave_dbh->selectall_arrayref('select * from test.t'),
   [[1],[2]],
   'DELETE replicated to slave'
);

$master_dbh->do("SET GLOBAL binlog_format='STATEMENT'");
$master_dbh->disconnect();
$master_dbh = $sb->get_dbh_for('master');

is_deeply(
   $master_dbh->selectrow_arrayref('select @@binlog_format'),
   ['STATEMENT'],
   'Set global binlog_format = STATEMENT'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
