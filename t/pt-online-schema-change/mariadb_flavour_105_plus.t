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
use File::Temp qw(tempfile);

use Data::Dumper;
use PerconaTest;
use Sandbox;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source', { mysql_ssl => 0 });

my $db_flavor = VersionParser->new($dbh)->flavor();

if ( $sandbox_version lt 10.5 || $db_flavor !~ m/maria/i ) {
   plan skip_all => "Test requires MariaDB 10.5+";
}
else {
   plan tests => 4;
}

# Prepare database and table
diag("Creating test database and table...");
$dbh->do("DROP DATABASE IF EXISTS test_flavor");
$dbh->do("CREATE DATABASE test_flavor");
$dbh->do("USE test_flavor");
$dbh->do("CREATE TABLE test_table (id INT PRIMARY KEY AUTO_INCREMENT, test_column VARCHAR(255))");
$dbh->do("INSERT INTO test_table VALUES(1, 'foobar')");
$dbh->do("COMMIT");

# Run pt-online-schema-change with your full options
my ($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main(
         "D=test_flavor,t=test_table,h=127.1,P=12345,u=msandbox,p=msandbox,s=0",
         "--alter", "ADD INDEX test_column_idx (test_column)",
         qw(--execute)
      )
   },
);

is(
   $exit_code,
   0,
   "pt-online-schema-change executed successfully"
);

unlike(
   $output,
   qr/flavor mismatch|not supported/i,
   "No flavor mismatch or unsupported error"
) or diag($output);

# Confirm index exists
$output = `/tmp/12345/use -Ne "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE INDEX_NAME = 'test_column_idx' AND TABLE_SCHEMA = 'test_flavor' AND TABLE_NAME = 'test_table'" 2>/dev/null`;

chomp $output;

is(
   $output,
   1,
   "Index 'test_column_idx' created"
);

# Cleanup
#$dbh->do("DROP DATABASE test_flavor");

# #############################################################################
# Done.
# #############################################################################

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;

