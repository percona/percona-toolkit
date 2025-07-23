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
use SqlModes;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

if ($sandbox_version lt '5.7') {
    plan skip_all => 'This test needs MySQL 5.7+ for general tablespace support';
} else {
    plan tests => 10;
}

my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args = qw(--set-vars innodb_lock_wait_timeout=3);
my $output;
my $exit_status;
my $dsn = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $sample = "t/pt-online-schema-change/samples";

# #############################################################################
# Test 1: Basic functionality - remove tablespace from table
# #############################################################################

$sb->load_file('source', "$sample/remove_tablespace.sql");

# Verify the table was created with tablespace
my $ddl = $source_dbh->selectrow_arrayref("SHOW CREATE TABLE test_ts.test_table");
like(
   $ddl->[1],
   qr/TABLESPACE `test_tablespace`/,
   "Table created with tablespace"
);

# Get original row count
my $orig_rows = $source_dbh->selectall_arrayref(
   "SELECT * FROM test_ts.test_table ORDER BY id"
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=test_ts,t=test_table",
         '--execute',
         '--alter', "ADD COLUMN new_col INT DEFAULT 42",
         '--remove-tablespace',
      )},
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Successfully altered table with --remove-tablespace"
);

like(
   $output,
   qr/Successfully altered/s,
   "Got successfully altered message"
);

# Verify tablespace was removed from the table
$ddl = $source_dbh->selectrow_arrayref("SHOW CREATE TABLE test_ts.test_table");
unlike(
   $ddl->[1],
   qr/TABLESPACE `test_tablespace`/,
   "Tablespace removed from table definition"
);

# Verify data integrity
my $new_rows = $source_dbh->selectall_arrayref(
   "SELECT id, name, created_at FROM test_ts.test_table ORDER BY id"
);
is_deeply(
   $new_rows,
   $orig_rows,
   "Data integrity maintained after removing tablespace"
);


# #############################################################################
# Test 3: Test with second table
# #############################################################################

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=test_ts,t=test_table2",
         '--execute',
         '--alter', "ADD COLUMN second_col BOOLEAN DEFAULT FALSE",
         '--remove-tablespace',
      )},
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Successfully altered second table with --remove-tablespace"
);

# Verify tablespace was removed from the second table
$ddl = $source_dbh->selectrow_arrayref("SHOW CREATE TABLE test_ts.test_table2");
unlike(
   $ddl->[1],
   qr/TABLESPACE `test_tablespace`/,
   "Tablespace removed from second table definition"
);

# #############################################################################
# Test 4: Test without --remove-tablespace (control test)
# #############################################################################

$sb->load_file('source', "$sample/remove_tablespace.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=test_ts,t=test_table",
         '--execute',
         '--alter', "ADD COLUMN control_col INT DEFAULT 0",
      )},
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Successfully altered table without --remove-tablespace"
);

# Verify tablespace is preserved when not using --remove-tablespace
$ddl = $source_dbh->selectrow_arrayref("SHOW CREATE TABLE test_ts.test_table");
like(
   $ddl->[1],
   qr/TABLESPACE `test_tablespace`/,
   "Tablespace preserved when not using --remove-tablespace"
);

# #############################################################################
# Cleanup
# #############################################################################

$source_dbh->do("DROP DATABASE IF EXISTS test_ts");
$source_dbh->do("DROP TABLESPACE test_tablespace");

$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;