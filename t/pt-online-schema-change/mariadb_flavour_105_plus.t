#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use Test::More;
use PerconaTest;
use DBI;
use File::Temp qw(tempfile);

my $dsn = "DBI:mysql:database=test_db;host=$ENV{DB_TEST_HOST};port=3306";
my $user = "$ENV{DB_TEST_USER}";       # MariaDB user
my $pass = "$ENV{DB_TEST_PASSWORD}";           # MariaDB password

my $dbh = DBI->connect($dsn, $user, $pass, { RaiseError => 1, PrintError => 0 })
    or die "Cannot connect to MariaDB: $DBI::errstr";

my $version = $dbh->selectrow_arrayref("SELECT VERSION()")->[0];

unless ($version =~ /mariadb/i && $version ge '10.5') {
    plan skip_all => "Test requires MariaDB 10.5+";
}

plan tests => 3;

# Prepare database and table
diag("Creating test database and table...");
$dbh->do("DROP DATABASE IF EXISTS test_flavor");
$dbh->do("CREATE DATABASE test_flavor");
$dbh->do("USE test_flavor");
$dbh->do("CREATE TABLE test_table (id INT PRIMARY KEY AUTO_INCREMENT, test_column VARCHAR(255))");

# Prepare tempfile for command output
my ($fh, $filename) = tempfile();

# Run pt-online-schema-change with your full options
my $cmd = join(' ',
    "$ENV{PERCONA_TOOLKIT_BRANCH}/bin/pt-online-schema-change",
    "--alter 'ADD INDEX test_column_idx (test_column)'",
    "--execute",
    "D=test_flavor,t=test_table,h=$ENV{DB_TEST_HOST},P=3306,u=$ENV{DB_TEST_USER},p=$ENV{DB_TEST_PASSWORD}",  # Adjust port/user/pass as needed
    "--sleep=0.2",
    "--recursion-method=processlist",
    "--pause-file=/tmp/pt-osc.pause",
    "--max-load Threads_running=100",
    "--critical-load Threads_running=140",
    "--max-lag=2",
    "--set-vars lock_wait_timeout=1",
    "--tries create_triggers:100:1,drop_triggers:100:1,copy_rows:1000:0.25,swap_tables:100:1,analyze_table:100:1",
    "--preserve-triggers",
    "--progress=percentage,5",
    "--no-drop-old-table",
    "> $filename 2>&1"
);

diag("Running pt-online-schema-change with full options...");
system($cmd);
ok($? == 0, "pt-online-schema-change executed successfully") or diag(`cat $filename`);

# Check output for flavor errors
open my $out, '<', $filename or die "Can't open $filename: $!";
my $content = do { local $/; <$out> };
close $out;

unlike($content, qr/flavor mismatch|not supported/i, "No flavor mismatch or unsupported error") or diag($content);

# Confirm index exists
my $index = $dbh->selectrow_arrayref("SHOW INDEX FROM test_flavor.test_table WHERE Key_name = 'test_column_idx'");
ok($index, "Index 'test_column_idx' created");

# Cleanup
$dbh->do("DROP DATABASE test_flavor");

done_testing;

