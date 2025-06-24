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

if ($sandbox_version lt '5.6') {
    plan skip_all => 'This test needs MySQL 5.6+';
} else {
    plan tests => 8;
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
# Test 1: Basic functionality - test regex removal
# #############################################################################

$sb->load_file('source', "$sample/remove_tablespace_file_per_table.sql");

# Get original row count
my $orig_rows = $source_dbh->selectall_arrayref(
   "SELECT * FROM test.test_table ORDER BY id"
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=test,t=test_table",
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

# Verify data integrity
my $new_rows = $source_dbh->selectall_arrayref(
   "SELECT id, name, created_at FROM test.test_table ORDER BY id"
);
is_deeply(
   $new_rows,
   $orig_rows,
   "Data integrity maintained after removing tablespace"
);

# #############################################################################
# Test 2: Dry-run mode - verify tablespace removal is planned
# #############################################################################

$sb->load_file('source', "$sample/remove_tablespace_file_per_table.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=test,t=test_table",
         '--dry-run', 
         '--alter', "ADD COLUMN dry_run_col VARCHAR(10)",
         '--remove-tablespace',
      )},
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Dry-run with --remove-tablespace exits successfully"
);

like(
   $output,
   qr/CREATE TABLE.*test_table.*\(/,
   "Dry-run shows CREATE TABLE statement"
);

# #############################################################################
# Test 3: Test without --remove-tablespace (control test)
# #############################################################################

$sb->load_file('source', "$sample/remove_tablespace_file_per_table.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=test,t=test_table",
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

# #############################################################################
# Test 4: Test regex functionality with manual tablespace addition
# #############################################################################

# Create a table and manually add a tablespace clause to test the regex
$source_dbh->do("DROP TABLE IF EXISTS test.test_table");
$source_dbh->do("CREATE TABLE test.test_table (
    id INT PRIMARY KEY,
    name VARCHAR(50)
) ENGINE=InnoDB");

# Manually modify the DDL to include a tablespace clause for testing
my $ddl = $source_dbh->selectrow_arrayref("SHOW CREATE TABLE test.test_table");
my $modified_ddl = $ddl->[1];
$modified_ddl =~ s/\) ENGINE=InnoDB/\) ENGINE=InnoDB TABLESPACE `test_tablespace`/;

# Create a temporary table with the modified DDL
$source_dbh->do("DROP TABLE IF EXISTS test.test_table");
$source_dbh->do($modified_ddl);

# Verify the table has the tablespace clause
$ddl = $source_dbh->selectrow_arrayref("SHOW CREATE TABLE test.test_table");
like(
   $ddl->[1],
   qr/TABLESPACE `test_tablespace`/,
   "Table created with manual tablespace clause"
);

# Test the --remove-tablespace functionality
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=test,t=test_table",
         '--execute', 
         '--alter', "ADD COLUMN regex_test_col INT DEFAULT 100",
         '--remove-tablespace',
      )},
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Successfully removed manually added tablespace clause"
);

# Verify tablespace clause was removed
$ddl = $source_dbh->selectrow_arrayref("SHOW CREATE TABLE test.test_table");
unlike(
   $ddl->[1],
   qr/TABLESPACE `test_tablespace`/,
   "Manually added tablespace clause was removed"
);

# #############################################################################
# Cleanup
# #############################################################################

$source_dbh->do("DROP DATABASE IF EXISTS test");

$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing; 