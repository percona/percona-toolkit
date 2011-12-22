#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

# TableSyncer and its required modules:
use OptionParser;
use NibbleIterator;
use TableSyncer;
use MasterSlave;
use Quoter;
use RowChecksum;
use Retry;
use TableParser;
use TableNibbler;
use TableParser;
use ChangeHandler;
use RowDiff;
use RowSyncer;
use RowSyncerBidirectional;
use RowChecksum;
use DSNParser;
use Cxn;
use Transformers;
use Sandbox;
use PerconaTest;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh      = $sb->get_dbh_for('master');
my $src_dbh  = $sb->get_dbh_for('master');
my $dst_dbh  = $sb->get_dbh_for('slave1');

if ( !$src_dbh || !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dst_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 33;
}

$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', 't/lib/samples/before-TableSyncChunk.sql');

# ###########################################################################
# Make a TableSyncer object.
# ###########################################################################
my $ms = new MasterSlave();
my $o  = new OptionParser(description => 'TableSyncer');
my $q  = new Quoter();
my $tp = new TableParser(Quoter => $q);
my $tn = new TableNibbler(TableParser => $tp, Quoter => $q);
my $rc = new RowChecksum(OptionParser => $o, Quoter => $q);
my $rd = new RowDiff(dbh=>$dbh);
my $rt = new Retry();

my $syncer = new TableSyncer(
   MasterSlave   => $ms,
   OptionParser  => $o,
   Quoter        => $q,
   TableParser   => $tp,
   TableNibbler  => $tn,
   RowChecksum   => $rc,
   RowDiff       => $rd,
   Retry         => $rt,
);
isa_ok($syncer, 'TableSyncer');

$o->get_specs("$trunk/bin/pt-table-sync");
$o->get_opts();

my $src_cxn = new Cxn(
   DSNParser    => $dp,
   OptionParser => $o,
   dsn_string   => "h=127.1,P=12345,u=msandbox,p=msandbox",
   dbh          => $src_dbh,
);
$src_cxn->{is_source} = 1;

my $dst_cxn = new Cxn(
   DSNParser    => $dp,
   OptionParser => $o,
   dsn_string   => "h=127.1,P=12346,u=msandbox,p=msandbox",
   dbh          => $dst_dbh,
);

# Global vars used/set by the subs below and accessed throughout the tests.
my $src;
my $dst;
my $tbl_struct;
my %actions;
my @rows;

sub new_ch {
   my ( $dbh, $queue ) = @_;
   my $ch = new ChangeHandler(
      Quoter    => $q,
      left_db   => $src->{tbl}->{db},
      left_tbl  => $src->{tbl}->{tbl},
      right_db  => $dst->{tbl}->{db},
      right_tbl => $dst->{tbl}->{tbl},
      actions => [
         sub {
            my ( $sql, $change_dbh ) = @_;
            push @rows, $sql;
            if ( $change_dbh ) {
               # dbh passed through change() or process_rows()
               $change_dbh->do($sql);
            }
            elsif ( $dbh ) {
               # dbh passed to this sub
               $dbh->do($sql);
            }
            else {
               # default dst dbh for this test script
               $dst_cxn->dbh()->do($sql);
            }
         }
      ],
      replace => 0,
      queue   => defined $queue ? $queue : 1,
   );
   $ch->fetch_back($src_cxn->dbh());
   return $ch;
}

# Shortens/automates a lot of the setup needed for calling
# TableSyncer::sync_table.  At minimum, you can pass just
# the src and dst args which are db.tbl args to sync. Various
# global vars are set: @rows, %actions, etc.
sub sync_table {
   my ( %args ) = @_;
   my ($src_db_tbl, $dst_db_tbl) = @args{qw(src dst)};
   my ($src_db, $src_tbl) = $q->split_unquote($src_db_tbl);
   my ($dst_db, $dst_tbl) = $q->split_unquote($dst_db_tbl);

   @ARGV = $args{argv} ? @{$args{argv}} : ();
   $o->get_opts();

   $tbl_struct = $tp->parse(
      $tp->get_create_table($src_cxn->dbh(), $src_db, $src_tbl));
   $src = {
      Cxn       => $src_cxn,
      misc_dbh  => $src_cxn->dbh(),
      tbl       => {
         db         => $src_db,
         tbl        => $src_tbl,
         tbl_struct => $tbl_struct,
      },
   };
   $dst = {
      Cxn      => $dst_cxn,
      misc_dbh => $src_cxn->dbh(),
      tbl      => {
         db         => $dst_db,
         tbl        => $dst_tbl,
         tbl_struct => $tbl_struct,
      },
   };
   @rows = ();
   my $ch = $args{ChangeHandler} || new_ch();
   my $rs = $args{RowSyncer}     || new RowSyncer(ChangeHandler => $ch,
                                                  OptionParser  => $o);
   return if $args{fake};
   %actions = $syncer->sync_table(
      src           => $src,
      dst           => $dst,
      RowSyncer     => $rs,
      ChangeHandler => $ch,
      trace         => 0,
      changing_src  => $args{changing_src},
      one_nibble    => $args{one_nibble},
   );
   return \%actions;
}

# ###########################################################################
# Test sync_table() for each plugin with a basic, 4 row data set.
# ###########################################################################

# test1 has 4 rows and test2, which is the same struct, is empty.
# So after sync, test2 should have the same 4 rows as test1.
my $test1_rows = [
 [qw(1 en)],
 [qw(2 ca)],
 [qw(3 ab)],
 [qw(4 bz)],
];
my $inserts = [
   "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('1', 'en')",
   "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('2', 'ca')",
   "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('3', 'ab')",
   "INSERT INTO `test`.`test2`(`a`, `b`) VALUES ('4', 'bz')",
];

# First, do a dry run sync, so nothing should happen.
$dst_dbh->do('TRUNCATE TABLE test.test2');

my $output = output(
   sub {
      sync_table(
         src  => "test.test1",
         dst  => "test.test2",
         argv => [qw(--explain)],
      );
   }
);

is_deeply(
   \%actions,
   {
      DELETE    => 0,
      INSERT    => 0,
      REPLACE   => 0,
      UPDATE    => 0,
   },
   'Dry run, no changes'
);

is_deeply(
   \@rows,
   [],
   'Dry run, no SQL statements made'
);

is_deeply(
   $dst_dbh->selectall_arrayref('SELECT * FROM test.test2 ORDER BY a, b'),
   [],
   'Dry run, no rows changed'
);

# Now do the real syncs that should insert 4 rows into test2.

sync_table(
   src => "test.test1",
   dst => "test.test2",
);

is_deeply(
   \%actions,
   {
      DELETE    => 0,
      INSERT    => 4,
      REPLACE   => 0,
      UPDATE    => 0,
   },
   'Basic sync 4 INSERT'
);

is_deeply(
   \@rows,
   $inserts,
   'Basic sync ChangeHandler INSERT statements'
);

is_deeply(
   $dst_dbh->selectall_arrayref('SELECT * FROM test.test2 ORDER BY a, b'),
   $test1_rows,
   'Basic sync dst rows match src rows'
);

# #############################################################################
# Check that the plugins can resolve unique key violations.
# #############################################################################
sync_table(
   src        => "test.test3",
   dst        => "test.test4",
   argv       => [qw(--chunk-size 1)],
   one_nibble => 0,
);

is_deeply(
   $dst_dbh->selectall_arrayref('select * from test.test4 order by a', { Slice => {}} ),
   [ { a => 1, b => 2 }, { a => 2, b => 1 } ],
   'Resolves unique key violations'
);

# ###########################################################################
# Test locking.
# ###########################################################################
sub clear_genlogs {
   my ($msg) = @_;
   if ( $msg ) {
      `echo "xxx $msg" >> /tmp/12345/data/genlog`;
      `echo "xxx $msg" >> /tmp/12346/data/genlog`;
   }
   else {
      `echo > /tmp/12345/data/genlog`;
      `echo > /tmp/12346/data/genlog`;
   }
   warn "cleared"
}

sync_table(
   src  => "test.test1",
   dst  => "test.test2",
   argv => [qw(--lock 1)],
);

# The locks should be released.
ok($src_dbh->do('select * from test.test4'), 'Chunk locks released');

sync_table(
   src  => "test.test1",
   dst  => "test.test2",
   argv => [qw(--lock 2)],
);

# The locks should be released.
ok($src_dbh->do('select * from test.test4'), 'Table locks released');

sync_table(
   src  => "test.test1",
   dst  => "test.test2",
   argv => [qw(--lock 3)],
);

ok(
   $dbh->do('replace into test.test3 select * from test.test3 limit 0'),
   'Does not lock in level 3 locking'
);

eval {
   $syncer->lock_and_wait(
      lock_level  => 3,
      host        => $src,
      src         => $src,
   );
};
is($EVAL_ERROR, '', 'Locks in level 3');

# See DBI man page.
use POSIX ':signal_h';
my $mask = POSIX::SigSet->new(SIGALRM);    # signals to mask in the handler
my $action = POSIX::SigAction->new( sub { die "maatkit timeout" }, $mask, );
my $oldaction = POSIX::SigAction->new();
sigaction( SIGALRM, $action, $oldaction );

throws_ok (
   sub {
      alarm 1;
      $dbh->do('replace into test.test3 select * from test.test3 limit 0');
   },
   qr/maatkit timeout/,
   "Level 3 lock NOT released",
);

# Kill the DBHs it in the right order: there's a connection waiting on
# a lock.
$src_cxn->dbh()->disconnect();
$dst_cxn->dbh()->disconnect();
$dst_cxn->connect();
$src_cxn->connect();

# ###########################################################################
# Test TableSyncGroupBy.
# ###########################################################################
$sb->load_file('master', 't/lib/samples/before-TableSyncGroupBy.sql');
PerconaTest::wait_for_table($dst_cxn->dbh(), "test.test2", "a=4");

sync_table(
   src     => "test.test1",
   dst     => "test.test2",
);

is_deeply(
   $dst_cxn->dbh()->selectall_arrayref('select * from test.test2 order by a, b, c', { Slice => {}} ),
   [
      { a => 1, b => 2, c => 3 },
      { a => 1, b => 2, c => 3 },
      { a => 1, b => 2, c => 3 },
      { a => 1, b => 2, c => 3 },
      { a => 2, b => 2, c => 3 },
      { a => 2, b => 2, c => 3 },
      { a => 2, b => 2, c => 3 },
      { a => 2, b => 2, c => 3 },
      { a => 3, b => 2, c => 3 },
      { a => 3, b => 2, c => 3 },
   ],
   'Table synced with GroupBy',
);

# #############################################################################
# Issue 96: mk-table-sync: Nibbler infinite loop
# #############################################################################
$sb->load_file('master', 't/lib/samples/issue_96.sql');
PerconaTest::wait_for_table($dst_cxn->dbh(), "issue_96.t2", "from_city='jr'");

# Make paranoid-sure that the tables differ.
my $r1 = $src_cxn->dbh()->selectall_arrayref('SELECT from_city FROM issue_96.t WHERE package_id=4');
my $r2 = $dst_cxn->dbh()->selectall_arrayref('SELECT from_city FROM issue_96.t2 WHERE package_id=4');
is_deeply(
   [ $r1->[0]->[0], $r2->[0]->[0] ],
   [ 'ta',          'zz'          ],
   'Infinite loop table differs (issue 96)'
);

sync_table(
   src => "issue_96.t",
   dst => "issue_96.t2",
);

$r1 = $src_cxn->dbh()->selectall_arrayref('SELECT from_city FROM issue_96.t WHERE package_id=4');
$r2 = $dst_cxn->dbh()->selectall_arrayref('SELECT from_city FROM issue_96.t2 WHERE package_id=4');

# Other tests below rely on this table being synced, so die
# if it fails to sync.
is(
   $r1->[0]->[0],
   $r2->[0]->[0],
   'Sync infinite loop table (issue 96)'
) or die "Failed to sync issue_96.t";

# #############################################################################
# Test check_permissions().
# #############################################################################

# Re-using issue_96.t from above.
is(
   $syncer->have_all_privs($src_cxn->dbh(), 'issue_96', 't'),
   1,
   'Have all privs'
);

diag(`/tmp/12345/use -u root -e "CREATE USER 'bob'\@'\%' IDENTIFIED BY 'bob'"`);
diag(`/tmp/12345/use -u root -e "GRANT select ON issue_96.t TO 'bob'\@'\%'"`);
my $bob_dbh = DBI->connect(
   "DBI:mysql:;host=127.0.0.1;port=12345", 'bob', 'bob',
      { PrintError => 0, RaiseError => 1 });

is(
   $syncer->have_all_privs($bob_dbh, 'issue_96', 't'),
   0,
   "Don't have all privs, just select"
);

diag(`/tmp/12345/use -u root -e "GRANT insert ON issue_96.t TO 'bob'\@'\%'"`);
is(
   $syncer->have_all_privs($bob_dbh, 'issue_96', 't'),
   0,
   "Don't have all privs, just select and insert"
);

diag(`/tmp/12345/use -u root -e "GRANT update ON issue_96.t TO 'bob'\@'\%'"`);
is(
   $syncer->have_all_privs($bob_dbh, 'issue_96', 't'),
   0,
   "Don't have all privs, just select, insert and update"
);

diag(`/tmp/12345/use -u root -e "GRANT delete ON issue_96.t TO 'bob'\@'\%'"`);
is(
   $syncer->have_all_privs($bob_dbh, 'issue_96', 't'),
   1,
   "Bob got his privs"
);

diag(`/tmp/12345/use -u root -e "DROP USER 'bob'"`);

# ###########################################################################
# Test that the calback gives us the src and dst sql.
# ###########################################################################
# Re-using issue_96.t from above.  The tables are already in sync so there
# should only be 1 sync cycle.

$output = output(
   sub {
      sync_table(
         src  => "issue_96.t",
         dst  => "issue_96.t2",
         argv => [qw(--chunk-size 1000 --explain)],
      );
   }
);

# TODO: improve this test
like(
   $output,
   qr/AS crc FROM `issue_96`.`t`/,
   "--explain"
);

# #############################################################################
# Issue 464: Make mk-table-sync do two-way sync
# #############################################################################
diag(`$trunk/sandbox/start-sandbox master 12348 >/dev/null`);
my $dbh3 = $sb->get_dbh_for('master1');
SKIP: {
   skip 'Cannot connect to sandbox master', 7 unless $dbh;
   skip 'Cannot connect to second sandbox master', 7 unless $dbh3;
   my $sync_chunk;

   # Switch "source" to master2 (12348).
   $dst_cxn = new Cxn(
      DSNParser    => $dp,
      OptionParser => $o,
      dsn_string   => "h=127.1,P=12345,u=msandbox,p=msandbox",
      dbh          => $dbh3,
   );

   # Proper data on both tables after bidirectional sync.
   my $bidi_data = 
      [
         [1,   'abc',   1,  '2010-02-01 05:45:30'],
         [2,   'def',   2,  '2010-01-31 06:11:11'],
         [3,   'ghi',   5,  '2010-02-01 09:17:52'],
         [4,   'jkl',   6,  '2010-02-01 10:11:33'],
         [5,   undef,   0,  '2010-02-02 05:10:00'],
         [6,   'p',     4,  '2010-01-31 10:17:00'],
         [7,   'qrs',   5,  '2010-02-01 10:11:11'],
         [8,   'tuv',   6,  '2010-01-31 10:17:20'],
         [9,   'wxy',   7,  '2010-02-01 10:17:00'],
         [10,  'z',     8,  '2010-01-31 10:17:08'],
         [11,  '?',     0,  '2010-01-29 11:17:12'],
         [12,  '',      0,  '2010-02-01 11:17:00'],
         [13,  'hmm',   1,  '2010-02-02 12:17:31'],
         [14,  undef,   0,  '2010-01-31 10:17:00'],
         [15,  'gtg',   7,  '2010-02-02 06:01:08'],
         [17,  'good',  1,  '2010-02-02 21:38:03'],
         [20,  'new', 100,  '2010-02-01 04:15:36'],
      ];

   # ########################################################################
   # First bidi test with chunk size=2, roughly 9 chunks.
   # ########################################################################
   # Load "master" data.
   $sb->load_file('master', 't/pt-table-sync/samples/bidirectional/table.sql');
   $sb->load_file('master', 't/pt-table-sync/samples/bidirectional/master-data.sql');
   # Load remote data.
   $sb->load_file('master1', 't/pt-table-sync/samples/bidirectional/table.sql');
   $sb->load_file('master1', 't/pt-table-sync/samples/bidirectional/remote-1.sql');

   # This is hack to get things setup correctly.
   sync_table(
      src           => "bidi.t",
      dst           => "bidi.t",
      ChangeHandler => 1,
      RowSyncer     => 1,
      fake          => 1,
   );
   my $ch = new_ch($dbh3, 0);
   my $rs = new RowSyncerBidirectional(
      ChangeHandler => $ch,
      OptionParser  => $o,
   );
   sync_table(
      src           => "bidi.t",
      dst           => "bidi.t",
      changing_src  => 1,
      argv          => [qw(--chunk-size 2
                           --conflict-error ignore
                           --conflict-column ts
                           --conflict-comparison newest)],
      ChangeHandler => $ch,
      RowSyncer     => $rs,
   );

   my $res = $src_cxn->dbh()->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      $bidi_data,
      'Bidirectional sync "master" (chunk size 2)'
   );

   $res = $dbh3->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      $bidi_data,
      'Bidirectional sync remote-1 (chunk size 2)'
   );

   # ########################################################################
   # Test it again with a larger chunk size, roughly half the table.
   # ########################################################################
   $sb->load_file('master', 't/pt-table-sync/samples/bidirectional/table.sql');
   $sb->load_file('master', 't/pt-table-sync/samples/bidirectional/master-data.sql');
   $sb->load_file('master1', 't/pt-table-sync/samples/bidirectional/table.sql');
   $sb->load_file('master1', 't/pt-table-sync/samples/bidirectional/remote-1.sql');

   # This is hack to get things setup correctly.
   sync_table(
      src           => "bidi.t",
      dst           => "bidi.t",
      ChangeHandler => 1,
      RowSyncer     => 1,
      fake          => 1,
   );
   $ch = new_ch($dbh3, 0);
   $rs = new RowSyncerBidirectional(
      ChangeHandler => $ch,
      OptionParser  => $o,
   );
   sync_table(
      src           => "bidi.t",
      dst           => "bidi.t",
      changing_src  => 1,
      argv          => [qw(--chunk-size 10
                           --conflict-error ignore
                           --conflict-column ts
                           --conflict-comparison newest)],
      ChangeHandler => $ch,
      RowSyncer     => $rs,
   );

   $res = $src_cxn->dbh()->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      $bidi_data,
      'Bidirectional sync "master" (chunk size 10)'
   );

   $res = $dbh3->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      $bidi_data,
      'Bidirectional sync remote-1 (chunk size 10)'
   );

   # ########################################################################
   # Chunk whole table.
   # ########################################################################
   $sb->load_file('master', 't/pt-table-sync/samples/bidirectional/table.sql');
   $sb->load_file('master', 't/pt-table-sync/samples/bidirectional/master-data.sql');
   $sb->load_file('master1', 't/pt-table-sync/samples/bidirectional/table.sql');
   $sb->load_file('master1', 't/pt-table-sync/samples/bidirectional/remote-1.sql');
   
   # This is hack to get things setup correctly.
   sync_table(
      src           => "bidi.t",
      dst           => "bidi.t",
      ChangeHandler => 1,
      RowSyncer     => 1,
      fake          => 1,
   );
   $ch = new_ch($dbh3, 0);
   $rs = new RowSyncerBidirectional(
      ChangeHandler => $ch,
      OptionParser  => $o,
   );
   sync_table(
      src           => "bidi.t",
      dst           => "bidi.t",
      changing_src  => 1,
      argv          => [qw(--chunk-size 1000
                           --conflict-error ignore
                           --conflict-column ts
                           --conflict-comparison newest)],
      ChangeHandler => $ch,
      RowSyncer     => $rs,
   );

   $res = $src_cxn->dbh()->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      $bidi_data,
      'Bidirectional sync "master" (whole table chunk)'
   );

   $res = $dbh3->selectall_arrayref('select * from bidi.t order by id');
   is_deeply(
      $res,
      $bidi_data,
      'Bidirectional sync remote-1 (whole table chunk)'
   );

   # ########################################################################
   # See TableSyncer.pm for why this is so.
   # ######################################################################## 
   # $args{ChangeHandler} = new_ch($dbh3, 1);
   # throws_ok(
   #   sub { $syncer->sync_table(%args, bidirectional => 1) },
   #   qr/Queueing does not work with bidirectional syncing/,
   #   'Queueing does not work with bidirectional syncing'
   #);

   diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null &`);

   # Set dest back to slave1 (12346).
   $dst_cxn = new Cxn(
      DSNParser    => $dp,
      OptionParser => $o,
      dsn_string   => "h=127.1,P=12346,u=msandbox,p=msandbox",
      dbh          => $dst_dbh,
   );
}

# #############################################################################
# Test with transactions.
# #############################################################################
# Sandbox::get_dbh_for() defaults to AutoCommit=1.  Autocommit must
# be off else commit() will cause an error.
$dbh = $sb->get_dbh_for('master', {AutoCommit=>0});
$src_cxn->dbh()->disconnect();
$dst_cxn->dbh()->disconnect();
$src_cxn->set_dbh($sb->get_dbh_for('master', {AutoCommit=>0}));
$dst_cxn->set_dbh($sb->get_dbh_for('slave1', {AutoCommit=>0}));

sync_table(
   src  => "test.test1",
   dst  => "test.test1",
   argv => [qw(--transaction --lock 1)],
);

# There are no diffs.  This just tests that the code doesn't crash
# when transaction is true.
is_deeply(
   \@rows,
   [],
   "Sync with transaction"
);

sync_table(
   src  => "sakila.actor",
   dst  => "sakila.actor",
   fake => 1,  # don't actually sync
);
$syncer->lock_and_wait(
   lock_level  => 1,
   host        => $src,
   src         => $src,
);


my $cid = $src_cxn->dbh()->selectrow_arrayref("SELECT CONNECTION_ID()")->[0];
$src_cxn->dbh()->do("SELECT * FROM sakila.actor WHERE 1=1 LIMIT 2 FOR UPDATE");
my $idb_status = $src_cxn->dbh()->selectrow_hashref("SHOW /*!40100 ENGINE*/ INNODB STATUS");
$src_cxn->dbh()->commit();
like(
   $idb_status->{status},
   qr/MySQL thread id $cid, query id \d+/,
   "Open transaction"
);

# #############################################################################
# Issue 672: mk-table-sync should COALESCE to avoid undef
# #############################################################################
$sb->load_file('master', "t/lib/samples/empty_tables.sql");
PerconaTest::wait_for_table($dst_cxn->dbh(), 'et.et1');

sync_table(
   src => 'et.et1',
   dst => 'et.et1',
);

is_deeply(
   \@rows,
   [],
   "Sync empty tables"
);

# #############################################################################
# Retry wait.
# #############################################################################
diag(`/tmp/12346/use -e "stop slave"`);
$output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   sync_table(
      src  => "sakila.actor",
      dst  => "sakila.actor",
      fake => 1,  # don't actually sync
      argv => [qw(--lock 1 --wait 60)],
   );
   throws_ok(
      sub {
         $syncer->lock_and_wait(
            lock_level      => 1,
            host            => $dst,
            src             => $src,
            wait_retry_args => {
               wait  => 1,
               tries => 2,
            },
         );
      },
      qr/Slave did not catch up to its master after 2 attempts of waiting 60/,
      "Retries wait"
   );
}
diag(`$trunk/sandbox/test-env reset`);

# #############################################################################
# Done.
# #############################################################################
{
   local *STDERR;
   open STDERR, '>', \$output;
   $syncer->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
$sb->wipe_clean($src_cxn->dbh());
$sb->wipe_clean($dst_cxn->dbh());
exit;
