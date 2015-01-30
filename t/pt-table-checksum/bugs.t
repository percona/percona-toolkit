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

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use Data::Dumper;
use PerconaTest;
use Sandbox;

require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave2_dbh = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-table-checksum/samples/";

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/995274
# Can't use an undefined value as an ARRAY reference at pt-table-checksum
# line 2206
# ############################################################################
$sb->load_file('master', "$sample/undef-arrayref-bug-995274.sql");

# Must chunk the table so an index is used.
$output = output(
   sub { $exit_status = pt_table_checksum::main(@args,
      qw(-d test --chunk-size 100)) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Bug 995274 (undef array): zero exit status"
) or diag($output);

cmp_ok(
   PerconaTest::count_checksum_results($output, 'rows'),
   '>',
   1,
   "Bug 995274 (undef array): checksummed rows"
);


# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/987393
# Empy tables cause "undefined value as an ARRAY" errors
# #############################################################################
$master_dbh->do("DROP DATABASE IF EXISTS percona");  # clear old checksums
$sb->load_file('master', "$sample/empty-table-bug-987393.sql");

$output = output(
   sub { $exit_status = pt_table_checksum::main(
      @args, qw(-d test --chunk-size-limit 0)) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Bug 987393 (empty table): zero exit status"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Bug 987393 (empty table): no errors"
);

my $rows = $master_dbh->selectall_arrayref("SELECT db, tbl, chunk, master_crc, master_cnt FROM percona.checksums ORDER BY db, tbl, chunk");
is_deeply(
   $rows,
   [
      ['test', 'test_empty', '1', '0',        '0'],  # empty
      ['test', 'test_full',  '1', 'ac967054', '1'],  # row
   ],
   "Bug 987393 (empty table): checksums"
) or print STDERR Dumper($rows);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/919499
# MySQL error 1592 with MySQL 5.5.18+ and Perl 5.8
# #############################################################################
$output = output(
   sub {
      print `$trunk/bin/pt-table-checksum $master_dsn -t sakila.country 2>&1`;
   }
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Bug 987393 (Perl 5.8 scoping): no errors"
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   109,
   "Bug 987393 (Perl 5.8 scoping): checksummed table"
);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1030031
# pt-table-checksum reports wrong number of DIFFS
# #############################################################################
$sb->load_file('master', "$sample/a-z.sql");
$sb->wait_for_slaves();

# Create 2 diffs on slave1 and 1 diff on slave2.
$slave1_dbh->do("UPDATE test.t SET c='' WHERE id=5");  # diff on slave1 & 2
$slave1_dbh->do("SET SQL_LOG_BIN=0");
$slave1_dbh->do("UPDATE test.t SET c='' WHERE id=20"); # diff only on slave1

# Restore sql_log_bin on slave1 in case later tests use it.
$slave1_dbh->do("SET SQL_LOG_BIN=1");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t test.t --chunk-size 10)) },
);

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   2,
   "Bug 1030031 (wrong DIFFS): 2 diffs"
);

# Restore slave2, but then give it 1 diff that's not the same chunk#
# as slave1, so there's 3 unique chunk that differ.
$slave2_dbh->do("UPDATE test.t SET c='e' WHERE id=5");
$slave2_dbh->do("UPDATE test.t SET c='' WHERE id=26");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t test.t --chunk-size 10)) },
);

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   3,
   "Bug 1030031 (wrong DIFFS): 3 diffs"
);

# #############################################################################
# pt-table-checksum does't ignore tables for --replicate-check-only
# https://bugs.launchpad.net/percona-toolkit/+bug/1074179
# #############################################################################

$output = output(
   sub { pt_table_checksum::main(@args, qw(--replicate-check-only --ignore-tables-regex=t)) },
   stderr => 1,
);

chomp($output);

is(
   $output,
   '',
   "Bug 1074179: ignore-tables-regex works with --replicate-check-only"
);
# #############################################################################
# pt-table-checksum can crash with --columns if none match
# https://bugs.launchpad.net/percona-toolkit/+bug/1016131
# #############################################################################

($output) = output(
   sub { pt_table_checksum::main(@args, '--tables', 'mysql.user,mysql.db',
                                 '--columns', 'some_fale_column') },
   stderr => 1,
);

like(
   $output,
   qr/\QSkipping table mysql.user because all columns are excluded by --columns or --ignore-columns/,
   "Bug 1016131: ptc should skip tables where all columns are excluded"
);

# #############################################################################
# Illegal division by zero at pt-table-checksum line 7950
# https://bugs.launchpad.net/percona-toolkit/+bug/1075638
# and the ptc part of
# divison by zero errors on default Gentoo mysql
# https://bugs.launchpad.net/percona-toolkit/+bug/1050737
# #############################################################################

{
   no warnings qw(redefine once);
   my $orig = \&Time::HiRes::time;
   my $time = Time::HiRes::time();
   local *pt_table_checksum::time = local *Time::HiRes::time = sub { $time };

   ($output) = output(
      sub { pt_table_checksum::main(@args,
               qw(--replicate=pt.checksums -t test.t --chunk-size 10))
      },
      stderr => 1
   );

   unlike(
      $output,
      qr/Illegal division by zero/,
      "Bugs 1075638 and 1050737: No division by zero error when nibble_time is zero"
   );

   is(
      PerconaTest::count_checksum_results($output, 'diffs'),
      3,
      "Bug 1075638 and 1050737: ...And we get the correct number of diffs"
   );
}

# #############################################################################
# pt-table-checksum doesn't warn if binlog_format=row or mixed on slaves
# https://bugs.launchpad.net/percona-toolkit/+bug/938068
# #############################################################################

SKIP: {
   skip "binlog_format tests require MySQL 5.1 and newer", 2
      unless $sandbox_version ge '5.1';

   local $ENV{BINLOG_FORMAT} = 'ROW';
   diag(`$trunk/sandbox/start-sandbox slave 12348 12345`);
   local $ENV{BINLOG_FORMAT} = 'MIXED';
   diag(`$trunk/sandbox/start-sandbox slave 12349 12348`);

   $output = output( sub { pt_table_checksum::main(@args) }, stderr => 1 );

   my $re = qr/Replica .+? has binlog_format (\S+)/msi;
   like(
      $output,
      $re,
      "Bug 938068: doesn't warn if binlog_format=row or mixed on slaves"
   );

   is_deeply(
      [ $output =~ /$re/g ],
      [ 'ROW', 'MIXED' ],
      "...and warns for both level 1 and level 2 slaves"
   ) or diag($output);

   diag(`$trunk/sandbox/stop-sandbox 12349 12348`);
}

# #############################################################################
# pt-table-checksum --recursion-method cluster crashes
# https://bugs.launchpad.net/percona-toolkit/+bug/1210537
# #############################################################################

$output = output(sub {
   pt_table_checksum::main($master_dsn,
      qw(--recursion-method cluster -t mysql.user)
   )},
   stderr => 1,
);
unlike(
   $output,
   qr/uninitialized value/,
   "Bug 1210537: no crash with --recursion-method cluster"
);
like(
   $output,
   qr/mysql.user/,
   "Bug 1210537: tool ran"
);

# #############################################################################
# pt-table-checksum has errors when slaves have different system_time_zone 
# https://bugs.launchpad.net/percona-toolkit/+bug/1388870 
# #############################################################################

# make slave set diferent system_time_zone by changing env var TZ. 
diag(`/tmp/12346/stop >/dev/null`); 
diag(`export TZ='HST';/tmp/12346/start >/dev/null`); 

$output = output(
   sub { pt_table_checksum::main(@args, qw(-t sakila.payment)) },
);


is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   0,
   "Bug 1388870 - No false positive reported when system_tz differ on slave"
);

# restore slave to original system_tz 
diag(`/tmp/12346/stop >/dev/null`); 
diag(`/tmp/12346/start >/dev/null`); 


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
