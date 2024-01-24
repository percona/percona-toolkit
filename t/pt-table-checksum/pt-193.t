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
use SqlModes;
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

# This table is being used by some other tests and it is not being properly cleaned
# so this tests fails sometimes. Just in case, clean the table but don't fail if the
# table doesn't exists.
eval {
    $dbh->do("TRUNCATE TABLE percona_test.load_data");
};

$sb->load_file('master', 't/lib/samples/issue_pt-193_backtick_in_col_comments.sql');

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = $sb->dsn_for('master');
my @args       = ($master_dsn, "--set-vars", "innodb_lock_wait_timeout=50", 
                               "--no-check-binlog-format", "--ignore-databases", "mysql",
                               "--nocheck-replication-filters"); 
my $output;
my $exit_status;

# Test #1 
$output = output(
   sub { $exit_status = pt_table_checksum::main(@args) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "PT-193 use single backtick in comments",
) or diag($output);

like(
    $output,
    qr/test\.t3/,
    "PT-193 table t3 was checksumed",
);


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
