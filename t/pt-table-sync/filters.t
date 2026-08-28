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

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');
my $replica_dbh  = $replica1_dbh;

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}
else {
   plan tests => 18;
}

my ($orig_binlog_format_source) = $source_dbh->selectrow_array(q{SELECT @@global.binlog_format});
my ($orig_binlog_format_replica1) = $replica1_dbh->selectrow_array(q{SELECT @@global.binlog_format});
my ($orig_binlog_format_replica2) = $replica2_dbh->selectrow_array(q{SELECT @@global.binlog_format});

$source_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$source_dbh->do("SET binlog_format = 'STATEMENT'");
$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$replica1_dbh->do("SET binlog_format = 'STATEMENT'");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$replica2_dbh->do("SET binlog_format = 'STATEMENT'");
$replica2_dbh->do("START ${replica_name}");

my $source_dsn = $sb->dsn_for('source');
my $replica1_dsn = $sb->dsn_for('replica1');
my $output;

# See this SQL file because it has a number of simple dbs and tbls
# that are used to checking schema object filters.
$sb->load_file('source', "t/lib/samples/SchemaIterator.sql");

sub test_filters {
   my (%args) = @_;

   $sb->clear_genlogs();

   my $output = output(
      sub { pt_table_sync::main(@{$args{cmds}},
         qw(--print))
      },
   );

   my $tables_used = PerconaTest::tables_used($sb->genlog('source'));
   is_deeply(
      $tables_used,
      $args{res},
      "$args{name}: tables used"
   ) or diag(Dumper($tables_used));
}

# #############################################################################
# Basic schema object filters: --databases, --tables, etc.
# #############################################################################

# Not really a filter, but only the specified tables should be used.
test_filters(
   name => "Sync d1.t1 to d1.t2",
   cmds => ["$source_dsn,D=d1,t=t1", "t=t2"],
   res  => [qw(d1.t1 d1.t2)],
);

# Use replica1 like it's another source, ok becuase we're not actually
# syncing anything, so --no-check-replica is required else pt-table-sync
# won't run (because it doesn't like to sync directly to a replica).
test_filters(
   name => "-t d1.t1",
   cmds => [$source_dsn, $replica1_dsn, qw(--no-check-replica),
            qw(-t d1.t1)],
   res  => [qw(d1.t1)],
);

# Like the previous test, but now any table called "t1".
test_filters(
   name => "-t t1",
   cmds => [$source_dsn, $replica1_dsn, qw(--no-check-replica),
            qw(-t t1)],
   res  => [qw(d1.t1 d2.t1)],
);

# Only the given db, all its tables: there's only 1 tbl in d2.
test_filters(
   name => "--databases d2",
   cmds => [$source_dsn, $replica1_dsn, qw(--no-check-replica),
            qw(--databases d2)],
   res  => [qw(d2.t1)],
);

# --database with --tables.
test_filters(
   name => "--databases d1 --tables t2,t3",
   cmds => [$source_dsn, $replica1_dsn, qw(--no-check-replica),
            qw(--databases d1), "--tables", "t2,t3"],
   res  => [qw(d1.t2 d1.t3)],
);

# #############################################################################
# Filters with --replicate and --sync-to-source.
# #############################################################################
   
# Checksum the filter tables.
$source_dbh->do("DROP DATABASE IF EXISTS percona");
$sb->wait_for_replicas();
diag(`$trunk/bin/pt-table-checksum $source_dsn -d d1,d2,d3 --chunk-size 100 --quiet --set-vars innodb_lock_wait_timeout=3 --max-load ''`);

my $rows = $source_dbh->selectall_arrayref("SELECT CONCAT(db, '.', tbl) FROM percona.checksums ORDER BY db, tbl");
is_deeply(
   $rows,
   [
      ["d1.t1"],
      ["d1.t2"],
      ["d1.t3"],
      ["d2.t1"],
   ],
   "Checksummed all tables"
) or diag(Dumper($rows));

# Make all checksums on the replica different than the source
# so that pt-table-sync would sync all the tables if there
# were no filters.
$replica_dbh->do("UPDATE percona.checksums SET this_cnt=999 WHERE 1=1");

# Verify that that ^ is true.
test_filters(
   name => "All tables are different on the replica",
   cmds => [$source_dsn, qw(--replicate percona.checksums)],
   res  => [qw(d1.t1 d1.t2 d1.t3 d2.t1 percona.checksums)],
);

# Sync with --replicate, --sync-to-source, and some filters.
# --replicate and --sync-to-source have different code paths,
# but the filter results should be the same.
foreach my $args (
   [$source_dsn, qw(--replicate percona.checksums)],
   [$replica1_dsn, qw(--replicate percona.checksums --sync-to-source)]
) {

   my $stm = $args->[-1] eq '--sync-to-source' ? ' --sync-to-source' : '';

   test_filters(
      name => $stm . " --replicate --tables t1",
      cmds => [@$args,
               qw(--tables t1)],
      res  => [qw(d1.t1 d2.t1 percona.checksums)],
   );

   test_filters(
      name => $stm . "--replicate --databases d2",
      cmds => [@$args,
               qw(--databases d2)],
      res  => [qw(d2.t1 percona.checksums)],
   );

   test_filters(
      name => $stm . "--replicate --databases d1 --tables t1,t3",
      cmds => [@$args,
               qw(--databases d1), "--tables", "t1,t3"],
      res  => [qw(d1.t1 d1.t3 percona.checksums)],
   );
}

# #############################################################################
# pt-table-sync --ignore-* options don't work with --replicate 
# https://bugs.launchpad.net/percona-toolkit/+bug/1002365
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->load_file("source", "t/pt-table-sync/samples/simple-tbls.sql");

# Create a checksum diff in a table that we're going to ignore
# when we sync.
$replica_dbh->do("INSERT INTO test.empty_it VALUES (null,11,11,'eleven')");

# Create the checksums.
diag(`$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox -d test --quiet --quiet --set-vars innodb_lock_wait_timeout=3 --max-load ''`);

# Make sure all the tables were checksummed.
$rows = $source_dbh->selectall_arrayref("SELECT DISTINCT db, tbl FROM percona.checksums ORDER BY db, tbl");
is_deeply(
   $rows,
   [ [qw(test empty_it) ],
     [qw(test empty_mt) ],
     [qw(test it1) ],
     [qw(test it2) ],
     [qw(test mt1) ],
     [qw(test mt2) ],
   ],
   "Six checksum tables (bug 1002365)"
);

# Sync the checksummed tables, but ignore the table with the diff we created.
$output = output(
   sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
      qw(--print --sync-to-source --replicate percona.checksums),
      "--ignore-tables", "test.empty_it") },
   stderr => 1,
);

is(
   $output,
   "",
   "Table ignored, nothing to sync (bug 1002365)"
);

# Sync the checksummed tables, but ignore the database.
$output = output(
   sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
      qw(--print --sync-to-source --replicate percona.checksums),
      "--ignore-databases", "test") },
   stderr => 1,
);

is(
   $output,
   "",
   "Database ignored, nothing to sync (bug 1002365)"
);

# The same should work for just --sync-to-source.
$output = output(
   sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
      qw(--print --sync-to-source),
      "--ignore-tables", "test.empty_it",
      "--ignore-databases", "percona") },
   stderr => 1,
);

unlike(
   $output,
   qr/empty_it/,
   "Table ignored, nothing to sync-to-source (bug 1002365)"
);

# #############################################################################
# Done.
# #############################################################################
$source_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_source}'");
$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_replica1}'");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_replica2}'");
$replica2_dbh->do("START ${replica_name}");
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
