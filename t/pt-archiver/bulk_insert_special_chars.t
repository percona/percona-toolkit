#!/usr/bin/env perl

# Test that pt-archiver --bulk-insert correctly escapes and preserves data
# containing tabs, newlines, and backslashes (no field misalignment).
# See: fix for escape() order (backslash first, then newline, then tab).

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
require "$trunk/bin/pt-archiver";

# Skip if sandbox not running (check before Sandbox uses /tmp/12345/use)
if ( !-x '/tmp/12345/use' ) {
   plan skip_all => 'Sandbox not running (start with sandbox/test-env start)';
   exit 0;
}

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
   exit 0;
}

my $cnf = "/tmp/12345/my.sandbox.cnf";

$sb->wipe_clean($dbh);
$sb->load_file('source', 't/pt-archiver/samples/bulk_insert_special_chars.sql');

# Rows with special characters: tab, newline, backslash, quotes.
# Using prepared statement so we pass actual characters (not SQL-escaped).
my @test_rows = (
   [ 1, 'John "Doe"', "Software Engineer\t\n", 123, 'Senior "Developer"' ],
   [ 2, 'Alice', "Data Scientist\nwith newline\n", 456, 'Lead Analyst' ],
   [ 3, 'Bob', "Engineer with tab\tcharacter\n", 789, 'Manager' ],
   [ 4, 'Charlie', "Backslash\\Test\n", 101, 'Director' ],
   [ 5, 'Eve', "Quote\'s Test\\t\n", 202, 'Consultant' ],
);

my $ins = $dbh->prepare(
   'INSERT INTO bulk_escape.source (id, name, job, stu_id, title) VALUES (?, ?, ?, ?, ?)'
);
for my $row ( @test_rows ) {
   $ins->execute(@$row);
}

# Archive from source to dest using --bulk-insert (purge source).
my $output = output(
   sub { pt_archiver::main(
      qw(--where 1=1 --bulk-insert --bulk-delete --limit 100 --statistics),
      '--source', "L=1,D=bulk_escape,t=source,F=$cnf",
      '--dest',   "D=bulk_escape,t=dest") },
);

# Verify row counts.
my $src_count = $dbh->selectrow_array('SELECT COUNT(*) FROM bulk_escape.source');
my $dst_count = $dbh->selectrow_array('SELECT COUNT(*) FROM bulk_escape.dest');
is($src_count, 0, 'Source table is purged');
is($dst_count, scalar(@test_rows), 'All rows archived to dest');

# Compare archived data with expected (order by id).
# Normalize numeric columns (id, stu_id) so comparison is robust across DBD::mysql
# returning integers or strings.
my $archived = $dbh->selectall_arrayref(
   'SELECT id, name, job, stu_id, title FROM bulk_escape.dest ORDER BY id'
);
my $normalized = [ map {
   [ 0 + $_->[0], $_->[1], $_->[2], 0 + $_->[3], $_->[4] ]
} @$archived ];
is_deeply($normalized, \@test_rows,
   'Bulk-insert preserves tabs, newlines, backslashes (no field misalignment)');

$sb->wipe_clean($dbh);
ok($sb->ok(), 'Sandbox servers') or BAIL_OUT(__FILE__ . ' broke the sandbox');
done_testing;
exit;
