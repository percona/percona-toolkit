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
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
elsif ( VersionParser->new($source_dbh) < '5.1.5' ) {
      plan skip_all => 'Requires MySQL 5.1.5 or newer';
}
else {
   plan tests => 7;
}

# #############################################################################
# Issue 95: Make mk-table-sync force statement-based binlog format on 5.1
# #############################################################################

$sb->create_dbs($source_dbh, ['test']);
$source_dbh->do('create table test.t (i int, unique index (i))');
$source_dbh->do('insert into test.t values (1),(2)');
$sb->wait_for_replicas();
$replica_dbh->do('insert into test.t values (3)');  # only on the replicas

is_deeply(
   $source_dbh->selectall_arrayref('select * from test.t order by i'),
   [[1],[2]],
   'Data on source before sync'
);

# Replicas have an extra row, something to sync.
my $rows = $replica_dbh->selectall_arrayref('select * from test.t order by i');
is_deeply(
   $rows,
   [[1],[2],[3]],
   'Data on replica before sync'
) or print Dumper($rows);

$source_dbh->do("SET GLOBAL binlog_format='ROW'");
$source_dbh->disconnect();
$source_dbh = $sb->get_dbh_for('source');

is_deeply(
   $source_dbh->selectrow_arrayref('select @@binlog_format'),
   ['ROW'],
   'Set global binlog_format = ROW'
);

is(
   output(
      sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
         qw(--sync-to-source -t test.t --print --execute)) },
      trf => \&remove_traces,
   ),
   "DELETE FROM `test`.`t` WHERE `i`='3' LIMIT 1;
",
   "Executed DELETE"
);

wait_until(
   sub {
      my $rows = $replica_dbh->selectall_arrayref('select * from test.t');
      return $rows && @$rows == 2;
   }
) or die "DELETE did not replicate to replica";

is_deeply(
   $replica_dbh->selectall_arrayref('select * from test.t'),
   [[1],[2]],
   'DELETE replicated to replica'
);

$source_dbh->do("SET GLOBAL binlog_format='STATEMENT'");
$source_dbh->disconnect();
$source_dbh = $sb->get_dbh_for('source');

is_deeply(
   $source_dbh->selectrow_arrayref('select @@binlog_format'),
   ['STATEMENT'],
   'Set global binlog_format = STATEMENT'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
