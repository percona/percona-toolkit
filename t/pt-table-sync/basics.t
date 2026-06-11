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
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
else {
   plan tests => 30;
}

$sb->create_dbs($source_dbh, [qw(test)]);

sub query_replica {
   return $replica_dbh->selectall_arrayref(@_, {Slice => {}});
}

sub run {
   my ($src, $dst, $other) = @_;
   my $output = output(
      sub {
         pt_table_sync::main(qw(--print --execute),
            "h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=$src,s=1",
            "h=127.1,P=12346,u=msandbox,p=msandbox,D=test,t=$dst,s=1",
            ($other ? split(" ", $other) : ())
         );
      },
      stderr => 1,
   );
   if ( $output ) {
      chomp $output;
      # Remove trace comments from end of change statements.
      $output = remove_traces($output);
   };
   return $output;
}

sub run_cmd {
   my ($src, $dst, $other) = @_;
   my $cmd = "$trunk/bin/pt-table-sync --print --execute h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=$src,s=1 h=127.1,P=12346,D=test,t=$dst,s=1 $other 2>&1";
   chomp($output=`$cmd`);
   return $output;
}

# #############################################################################
# Test basic source-replica syncing
# #############################################################################
$sb->load_file('source', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '');
like($output, qr/Can't make changes/, 'It dislikes changing a replica');

$output = run('test1', 'test2', '--no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'No alg sync');
is_deeply(
   query_replica('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with no alg'
);

$sb->load_file('source', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '--algorithms Stream --no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'Basic Stream sync');
is_deeply(
   query_replica('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with Stream'
);

$sb->load_file('source', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '--algorithms GroupBy --no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'Basic GroupBy sync');
is_deeply(
   query_replica('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with GroupBy'
);

$sb->load_file('source', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '--algorithms Chunk,GroupBy --no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'Basic Chunk sync');
is_deeply(
   query_replica('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with Chunk'
);

# Create a new user that is going to be replicated on replicas.
# After that, stop replication, delete the user from the source just to ensure that
# on the source we are using the sandbox user, and start relication again to run
# the tests
$sb->do_as_root("source", q/CREATE USER 'replica_user'@'%' IDENTIFIED BY 'replica_password'/);
$sb->do_as_root("source", q/GRANT REPLICATION SLAVE ON *.* TO 'replica_user'@'%'/);
$sb->do_as_root("source", q/set sql_log_bin=0/);
$sb->do_as_root("source", q/DROP USER 'replica_user'/);
$sb->do_as_root("source", q/set sql_log_bin=1/);

$sb->load_file('source', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '--algorithms Chunk,GroupBy --no-bin-log --replica-user replica_user --replica-password replica_password');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'Basic Chunk sync');
is_deeply(
   query_replica('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with --replica-user'
);

unlike(
   $output,
   qr/Option --slave-user is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --replica-user provided'
) or diag($output);

unlike(
   $output,
   qr/Option --slave-password is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --replica-password provided'
) or diag($output);

$sb->load_file('source', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '--algorithms Chunk,GroupBy --no-bin-log --slave-user replica_user --slave-password replica_password');

like(
   $output, 
   qr/INSERT INTO `test`.`test2`\(`a`, `b`\) VALUES \('1', 'en'\);\nINSERT INTO `test`.`test2`\(`a`, `b`\) VALUES \('2', 'ca'\);/, 
   'Basic Chunk sync with --slave-user/--slave-password'
);

is_deeply(
   query_replica('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with --slave-user'
);

like(
   $output,
   qr/Option --slave-user is deprecated and will be removed in future versions./,
   'Deprecation warning printed when option --slave-user provided'
) or diag($output);

like(
   $output,
   qr/Option --slave-password is deprecated and will be removed in future versions./,
   'Deprecation warning printed when option --slave-password provided'
) or diag($output);

$sb->load_file('source', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '--algorithms Nibble --no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'Basic Nibble sync');
is_deeply(
   query_replica('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with Nibble'
);

# Save original PTDEBUG env because we modify it below.
my $dbg = $ENV{PTDEBUG};

$sb->load_file('source', 't/pt-table-sync/samples/before.sql');
$ENV{PTDEBUG} = 1;
$output = run_cmd('test1', 'test2', '--algorithms Nibble --no-bin-log --chunk-size 1 --transaction --lock 1');
delete $ENV{PTDEBUG};
like(
   $output,
   qr/Executing statement on source/,
   'Nibble with transactions and locking'
);
is_deeply(
   query_replica('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with Nibble'
);

# Sync tables that have values with leading zeroes
$ENV{PTDEBUG} = 1;
$output = run('test3', 'test4', '--print --no-bin-log --verbose --function MD5');
delete $ENV{PTDEBUG};
like(
   $output,
   qr/UPDATE `test`.`test4`.*51707/,
   'Found the first row',
);
like(
   $output,
   qr/UPDATE `test`.`test4`.*'001'/,
   'Found the second row',
);
like(
   $output,
   qr/2 Chunk\s+\S+\s+\S+\s+2\s+test.test3/,
   'Right number of rows to update',
);

# Sync a table with Nibble and a chunksize in data size, not number of rows
$output = run('test3', 'test4', '--algorithms Nibble --chunk-size 1k --print --verbose --function MD5');
# If it lived, it's OK.
ok($output, 'Synced with Nibble and data-size chunksize');

# Restore PTDEBUG env.
$ENV{PTDEBUG} = $dbg || 0;

# ###########################################################################
# Fix bug 911996.
# ###########################################################################

# pt-table-checksum waits for all checksums to replicate to all replicas,
# so no need to call $sb->wait_for_replicas() after this.
`$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox --max-load '' --set-vars innodb_lock_wait_timeout=3 --chunk-size 50 --chunk-index idx_actor_last_name -t sakila.actor --quiet`;

$replica_dbh->do("update percona.checksums set this_crc='' where db='sakila' and tbl='actor' and chunk=3");
$replica_dbh->do("update sakila.actor set last_name='' where actor_id=30");
$sb->wait_for_replicas(); # wait for those ^ updates to replicate to replica2 (!2347)

$output = output(
   sub {
      pt_table_sync::main('h=127.1,P=12345,u=msandbox,p=msandbox',
         qw(--print --execute --replicate percona.checksums),
         qw(--no-foreign-key-checks --no-check-child-tables))
   }
);

like(
   $output,
   qr/^REPLACE INTO `sakila`.`actor`\(`actor_id`, `first_name`, `last_name`, `last_update`\) VALUES \('30', 'SANDRA', 'PECK', '2006-02-15 11:34:33'\)/,
   "--replicate with char index col (bug 911996)"
);

$output = `$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox --max-load '' --set-vars innodb_lock_wait_timeout=3 --chunk-size 50 --chunk-index idx_actor_last_name -t sakila.actor`;
is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   0,
   "Synced diff (bug 911996)"
);

# Fix bug 927771.
$sb->load_file('source', 't/pt-table-sync/samples/bug_927771.sql');
$replica_dbh->do("update test.t set c='z' where id>8");

# pt-table-checksum waits for all checksums to replicate to all replicas,
# so no need to call $sb->wait_for_replicas() after this.
`$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox --max-load '' --set-vars innodb_lock_wait_timeout=3 --chunk-size 2 -t test.t --quiet`;

$output = output(
   sub {
      pt_table_sync::main('h=127.1,P=12346,u=msandbox,p=msandbox',
          #         qw(--print --execute --replicate percona.checksums),
         qw(--print --execute --sync-to-source),
         qw(--no-foreign-key-checks))
   },
   stderr => 1,
);

$sb->wait_for_replicas();  # wait for sync to replicate

like(
   $output,
   qr/REPLACE INTO `test`.`t`\(`id`, `c`\) VALUES \('9', 'i'\)/,
   "--replicate with uc index (bug 927771)"
);

my $rows = $replica_dbh->selectall_arrayref("select id, c from test.t where id>8 order by id");

is_deeply(
   $rows,
   [
      [9,  'i'],
      [10, 'j'],
   ],
   "Synced replicad (bug 927771)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
