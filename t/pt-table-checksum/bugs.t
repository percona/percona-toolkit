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

# Fix @INC because pt-table-checksum uses subclass OobNibbleIterator.
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
else {
   plan tests => 5;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--lock-wait-timeout 3));
my $output;
my $exit_status;
my $sample  = "t/pt-table-checksum/samples/";

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/995274
# Can't use an undefined value as an ARRAY reference at pt-table-checksum
# line 2206
# ############################################################################
$sb->load_file('master', "$sample/undef-arrayref-bug-995274.sql");
PerconaTest::wait_for_table($slave_dbh, "test.GroupMembers", "id=493076");

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
);

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
PerconaTest::wait_for_table($slave_dbh, "test.test_full", "id=1");

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
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
