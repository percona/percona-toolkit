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

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 17;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3 --explain --chunk-size 3), '--max-load', '');
my $output;
my $out        = "t/pt-table-checksum/samples/";

$sb->load_file('master', "t/pt-table-checksum/samples/issue_519.sql");

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(-t issue_519.t --explain)) },
      "$out/chunkidx001.txt",
   ),
   "Chooses chunk index by default"
);

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-index dog),
         qw(-t issue_519.t --explain)) },
      "$out/chunkidx001.txt",
   ),
   "Chooses chunk index if --chunk-index doesn't exist"
);

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-index myidx),
         qw(-t issue_519.t --explain)) },
      "$out/chunkidx002.txt",
   ),
   "Use --chunk-index"
);

# XXX I'm not sure what this tests thinks it's testing because index y
# is a single column index, so there's really not "left-most".
ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-index y),
         qw(-t issue_519.t --explain)) },
      "$out/chunkidx003.txt",
   ),
   "Chunks on left-most --chunk-index column"
);

# #############################################################################
# Issue 378: Make mk-table-checksum try to use the index preferred by the
# optimizer
# #############################################################################

# This issue affect --chunk-index.  Tool should auto-choose chunk-index
# when --where is given but no explicit --chunk-index|column is given.
# Given the --where clause, MySQL will prefer the idx_fk_country_id index.

ok(
   no_diff(
      sub { pt_table_checksum::main(@args, "--where", "country_id > 100",
         qw(-t sakila.city)) },
      "$out/chunkidx004.txt",
   ),
   "Auto-chosen --chunk-index for --where (issue 378)"
);

# If user specifies --chunk-index, then ignore the index MySQL wants to
# use (idx_fk_country_id in this case) and use the user's index.
ok(
   no_diff(
      sub { pt_table_checksum::main(@args, qw(--chunk-index PRIMARY),
         "--where", "country_id > 100", qw(-t sakila.city)) },
      "$out/chunkidx005.txt",
   ),
   "Explicit --chunk-index overrides MySQL's index for --where"
);

# #############################################################################
# Bug 925855: pt-table-checksum index check is case-sensitive
# #############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/all-uc-table.sql");
my $exit_status = 0;
$output = output(sub {
   $exit_status = pt_table_checksum::main(
      $master_dsn, '--max-load', '',
      qw(--set-vars innodb_lock_wait_timeout=3 --chunk-size 5 -t ALL_UC.T)
   ) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Zero exit status (bug 925855)"
);

is(
   PerconaTest::count_checksum_results($output, 'skipped'),
   0,
   "0 skipped (bug 925855)"
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "0 errors (bug 925855)"
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   13,
   "14 rows checksummed (bug 925855)"
);

# #############################################################################
# Bug 978432: PK is ignored
# #############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/not-using-pk-bug.sql");

ok(
   no_diff(
      sub { pt_table_checksum::main(@args,
         qw(-t test.multi_resource_apt --chunk-size 2 --explain --explain))
      },
      "t/pt-table-checksum/samples/not-using-pk-bug.out",
   ),
   "Smarter chunk index selection (bug 978432)"
);

# #############################################################################
# PK but bad explain plan.
# https://bugs.launchpad.net/percona-toolkit/+bug/1010232
# #############################################################################
$sb->load_file('master', "t/pt-table-checksum/samples/bad-plan-bug-1010232.sql");
PerconaTest::wait_for_table($dbh, "bad_plan.t", "(c1,c2,c3,c4)=(1,1,2,100)");

$output = output(sub {
   $exit_status = pt_table_checksum::main(
      $master_dsn, '--max-load', '',
      qw(--set-vars innodb_lock_wait_timeout=3 --chunk-size 10 -t bad_plan.t)
   ) },
   stderr => 1,
);

is(
   $exit_status,
   32,  # SKIP_CHUNK
   "Bad key_len chunks are not errors"
) or diag($output);

cmp_ok(
   PerconaTest::count_checksum_results($output, 'skipped'),
   '>',
   1,
   "Skipped bad key_len chunks"
);

# Use --chunk-index:3 to use only the first 3 left-most columns of the index.
# Can't use bad_plan.t, however, because its row are almost all identical,
# so using 3 of 4 pk cols creates an infinite loop.
ok(
   no_diff(
      sub {
         pt_table_checksum::main(
            $master_dsn, '--max-load', '',
            qw(--set-vars innodb_lock_wait_timeout=3 --chunk-size 5000  -t sakila.rental),
            qw(--chunk-index rental_date --chunk-index-columns 2),
            qw(--explain --explain));
      },
      "t/pt-table-checksum/samples/n-chunk-index-cols.txt",
   ),
   "--chunk-index-columns"
);

$output = output(         
   sub {
      $exit_status = pt_table_checksum::main(
         $master_dsn, '--max-load', '',
         qw(--set-vars innodb_lock_wait_timeout=3 --chunk-size 1000  -t sakila.film_actor),
         qw(--chunk-index PRIMARY --chunk-index-columns 9),
      );
   },
   stderr => 1,
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   5462,
   "--chunk-index-columns > number of index columns"
) or diag($output);

$output = output(         
   sub {
      $exit_status = pt_table_checksum::main(
         $master_dsn, '--max-load', '',
         qw(--set-vars innodb_lock_wait_timeout=3 --chunk-size 1000 -t sakila.film_actor),
         qw(--chunk-index-columns 1 --chunk-size-limit 3),
      );
   },
   stderr => 1,
);

# Since we're not using the full index, it's basically a non-unique index,
# so there are dupes.  The table really has 5462 rows, so we must get
# at least that many, and probably a few more.
cmp_ok(
   PerconaTest::count_checksum_results($output, 'rows'),
   '>=',
   5462,
   "Initial key_len reflects --chunk-index-columns"
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
