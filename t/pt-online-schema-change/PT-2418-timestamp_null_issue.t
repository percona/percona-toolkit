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

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');

if ($sandbox_version lt '8.0') {
    plan skip_all => 'This test needs MySQL 8.0+';
} elsif ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# ############################################################################
# Test for timestamp NULL issue during column rename
# This reproduces the issue where 't' column values become NULL after CHANGE COLUMN
# ############################################################################

$sb->load_file('source', "$sample/PT-2418-timestamp_null_issue.sql");

# Get the original data before the rename operation
my $orig_data = $source_dbh->selectall_arrayref(
   "SELECT i, s, t1, g FROM test.joinit ORDER BY i"
);

# Verify we have data with non-NULL timestamps
ok(
   scalar(@$orig_data) > 0,
   "Table has data before rename operation"
);

# Check that timestamps are not NULL
my $null_timestamps = 0;
foreach my $row (@$orig_data) {
   $null_timestamps++ if !defined($row->[2]); # column 't' is at index 2
}

is(
   $null_timestamps,
   0,
   "All timestamp values are non-NULL before rename operation"
) or diag("Found $null_timestamps NULL timestamps out of " . scalar(@$orig_data) . " rows");

# Test if --check-alter works correctly
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=test,t=joinit",
      "--alter", "RENAME COLUMN t1 TO t2",
      qw(--execute --check-alter)) },
);

is(
   $exit_status,
   17,
   "Column rename operation rejected correctly"
) or diag($output);

like(
   $output,
   qr/`test`.`joinit` was not altered./,
   "Table was not altered"
);

# Perform the column rename operation
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=test,t=joinit",
      "--alter", "RENAME COLUMN t1 TO t2",
      qw(--execute --no-check-alter)) },
);

is(
   $exit_status,
   0,
   "Column rename operation completed successfully"
) or diag($output);

# Get the data after the rename operation
my $new_data = $source_dbh->selectall_arrayref(
   "SELECT i, s, t2, g FROM test.joinit ORDER BY i"
);

# Verify the data structure is the same
is(
   scalar(@$new_data),
   scalar(@$orig_data),
   "Same number of rows after rename operation"
);

# Check that timestamps are preserved (not NULL)
$null_timestamps = 0;
foreach my $row (@$new_data) {
   $null_timestamps++ if !defined($row->[2]); # column 't1' is now at index 2
}

is(
   $null_timestamps,
   0,
   "All timestamp values are preserved (non-NULL) after rename operation"
) or diag("Found $null_timestamps NULL timestamps out of " . scalar(@$new_data) . " rows");

# Compare the actual timestamp values (ignoring the column name change)
for (my $i = 0; $i < scalar(@$orig_data); $i++) {
   is(
      $new_data->[$i]->[2], # t1 column value
      $orig_data->[$i]->[2], # original t column value
      "Timestamp value preserved for row " . ($i + 1)
   ) or diag("Row " . ($i + 1) . ": Original=" . 
             (defined($orig_data->[$i]->[2]) ? $orig_data->[$i]->[2] : "NULL") . 
             ", New=" . (defined($new_data->[$i]->[2]) ? $new_data->[$i]->[2] : "NULL"));
}

# Test the reverse rename operation
($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=test,t=joinit",
      "--alter", "CHANGE COLUMN t2 t1 time NOT NULL",
      qw(--execute --no-check-alter)) },
);

is(
   $exit_status,
   0,
   "Reverse column rename operation completed successfully"
) or diag($output);

# Get the data after the reverse rename
my $final_data = $source_dbh->selectall_arrayref(
   "SELECT i, s, t1, g FROM test.joinit ORDER BY i"
);

# Verify timestamps are still preserved
$null_timestamps = 0;
foreach my $row (@$final_data) {
   $null_timestamps++ if !defined($row->[2]); # column 't' is back at index 2
}

is(
   $null_timestamps,
   0,
   "All timestamp values are preserved (non-NULL) after reverse rename operation"
) or diag("Found $null_timestamps NULL timestamps out of " . scalar(@$final_data) . " rows");

# Compare with original data
for (my $i = 0; $i < scalar(@$orig_data); $i++) {
   is(
      $final_data->[$i]->[2], # t column value
      $orig_data->[$i]->[2], # original t column value
      "Timestamp value preserved after reverse rename for row " . ($i + 1)
   ) or diag("Row " . ($i + 1) . ": Original=" . 
             (defined($orig_data->[$i]->[2]) ? $orig_data->[$i]->[2] : "NULL") . 
             ", Final=" . (defined($final_data->[$i]->[2]) ? $final_data->[$i]->[2] : "NULL"));
}

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing; 
