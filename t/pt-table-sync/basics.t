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
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 22;
}

$sb->create_dbs($master_dbh, [qw(test)]);

sub query_slave {
   return $slave_dbh->selectall_arrayref(@_, {Slice => {}});
}

sub run {
   my ($src, $dst, $other) = @_;
   my $output = output(
      sub {
         pt_table_sync::main(qw(--print --execute),
            "h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=$src",
            "h=127.1,P=12346,u=msandbox,p=msandbox,D=test,t=$dst",
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
   my $cmd = "$trunk/bin/pt-table-sync --print --execute h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=$src h=127.1,P=12346,D=test,t=$dst $other 2>&1";
   chomp($output=`$cmd`);
   return $output;
}

# #############################################################################
# Test basic master-slave syncing
# #############################################################################
$sb->load_file('master', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '');
like($output, qr/Can't make changes/, 'It dislikes changing a slave');

$output = run('test1', 'test2', '--no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'No alg sync');
is_deeply(
   query_slave('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with no alg'
);

$sb->load_file('master', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '--algorithms Stream --no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'Basic Stream sync');
is_deeply(
   query_slave('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with Stream'
);

$sb->load_file('master', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '--algorithms GroupBy --no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'Basic GroupBy sync');
is_deeply(
   query_slave('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with GroupBy'
);

$sb->load_file('master', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '--algorithms Chunk,GroupBy --no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'Basic Chunk sync');
is_deeply(
   query_slave('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with Chunk'
);

$sb->load_file('master', 't/pt-table-sync/samples/before.sql');
$output = run('test1', 'test2', '--algorithms Nibble --no-bin-log');
is($output, "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en');
INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca');", 'Basic Nibble sync');
is_deeply(
   query_slave('select * from test.test2'),
   [ {   a => 1, b => 'en' }, { a => 2, b => 'ca' } ],
   'Synced OK with Nibble'
);

# Save original PTDEBUG env because we modify it below.
my $dbg = $ENV{PTDEBUG};

$sb->load_file('master', 't/pt-table-sync/samples/before.sql');
$ENV{PTDEBUG} = 1;
$output = run_cmd('test1', 'test2', '--algorithms Nibble --no-bin-log --chunk-size 1 --transaction --lock 1');
delete $ENV{PTDEBUG};
like(
   $output,
   qr/Executing statement on source/,
   'Nibble with transactions and locking'
);
is_deeply(
   query_slave('select * from test.test2'),
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

# pt-table-checksum waits for all checksums to replicate to all slaves,
# so no need to call $sb->wait_for_slaves() after this.
`$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox --max-load '' --set-vars innodb_lock_wait_timeout=3 --chunk-size 50 --chunk-index idx_actor_last_name -t sakila.actor --quiet`;

$slave_dbh->do("update percona.checksums set this_crc='' where db='sakila' and tbl='actor' and chunk=3");
$slave_dbh->do("update sakila.actor set last_name='' where actor_id=30");
$sb->wait_for_slaves(); # wait for those ^ updates to replicate to slave2 (!2347)

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
$sb->load_file('master', 't/pt-table-sync/samples/bug_927771.sql');
$slave_dbh->do("update test.t set c='z' where id>8");

# pt-table-checksum waits for all checksums to replicate to all slaves,
# so no need to call $sb->wait_for_slaves() after this.
`$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox --max-load '' --set-vars innodb_lock_wait_timeout=3 --chunk-size 2 -t test.t --quiet`;

$output = output(
   sub {
      pt_table_sync::main('h=127.1,P=12345,u=msandbox,p=msandbox',
         qw(--print --execute --replicate percona.checksums),
         qw(--no-foreign-key-checks))
   },
   stderr => 1,
);

$sb->wait_for_slaves();  # wait for sync to replicate

like(
   $output,
   qr/REPLACE INTO `test`.`t`\(`id`, `c`\) VALUES \('9', 'i'\)/,
   "--replicate with uc index (bug 927771)"
);

my $rows = $slave_dbh->selectall_arrayref("select id, c from test.t where id>8 order by id");
is_deeply(
   $rows,
   [
      [9,  'i'],
      [10, 'j'],
   ],
   "Synced slaved (bug 927771)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
