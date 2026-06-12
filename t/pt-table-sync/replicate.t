#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";

   # Don't add /* trace */ messages to --print queries becuase they
   # contain non-determinstic info like user, etc.
   $ENV{PT_TEST_NO_TRACE} = 1;
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}

my $source_dsn = $sb->dsn_for('source');
my $replica1_dsn = $sb->dsn_for('replica1');

my $output;
my $sample = "t/pt-table-sync/samples";

# #############################################################################
# --replicate tests
# #############################################################################

# #############################################################################
# Bug 918056: pt-table-sync false-positive error "Cannot nibble table because
# MySQL chose no index instead of the PRIMARY index"
# https://bugs.launchpad.net/percona-toolkit/+bug/918056
# #############################################################################

# The replica has 49 extra rows on the low end, e.g. source has rows 50+
# but replica has rows 1-49 and 50+.  This tests syncing the lower oob chunk.
$sb->create_dbs($source_dbh, [qw(bug918056)]);
$sb->load_file('source', "$sample/bug-918056-master.sql", "bug918056");
$sb->load_file('replica1', "$sample/bug-918056-slave.sql",  "bug918056");

ok(
   no_diff(
      sub {
         pt_table_sync::main($source_dsn, qw(--replicate percona.checksums),
            qw(--print))
      },
      "$sample/bug-918056-print.txt",
      stderr => 1,
   ),
   "Sync lower oob (bug 918056)"
);

# Test syncing the upper oob chunk.
$sb->load_file('source', "$sample/upper-oob-master.sql");
$sb->load_file('replica1', "$sample/upper-oob-slave.sql");

ok(
   no_diff(
      sub {
         pt_table_sync::main($source_dsn, qw(--replicate percona.checksums),
            qw(--print))
      },
      "$sample/upper-oob-print.txt",
      stderr => 1,
   ),
   "Sync upper oob (bug 918056)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica1_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
