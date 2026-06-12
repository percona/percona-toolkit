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

#if ( !$ENV{SLOW_TESTS} ) { 
#   plan skip_all => "pt-table-checksum/pt-1616.t is one of the top slowest files; set SLOW_TESTS=1 to enable it.";
#}

use PerconaTest;
use Sandbox;
use SqlModes;
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
    plan skip_all => 'Cannot connect to sandbox source';
}
else {
    plan tests => 4;
}

diag("loading samples");
$sb->load_file('source', 't/pt-table-checksum/samples/pt-1616.sql');

my $num_rows = 50000;
diag("Loading $num_rows rows into the table. This might take some time.");
# diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox junk pt_test_100 $num_rows`);

my $sql = "INSERT INTO junk.pt_test_100 (id1, id2) VALUES (?, ?)";
my $sth = $dbh->prepare($sql);
my @chars = ("A".."Z", "a".."z");

# Generate some random data haivng commas
for (my $i=0; $i < $num_rows; $i++) {
    # Generate random strings having commas
    my ($id1, $id2) = (",,,,", ",,,,");
    $id1 .= $chars[rand @chars] for 1..10;
    $id2 .= $chars[rand @chars] for 1..10;
    
    $sth->execute($id1, $id2);
}
$sth->finish();
$dbh->do('INSERT INTO junk.pt_test_100 (id1, id2) VALUES(UNHEX("F96DD7"), UNHEX("F96DD7"))');

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
my $source_dsn = $sb->dsn_for('source');

my @args = ($source_dsn, "--set-vars", "innodb_lock_wait_timeout=50", 
    "--ignore-databases", "mysql", "--no-check-binlog-format", 
    "--chunk-size", "1", 
    "--empty-replicate-table", "--run-time", "2s"
);

my $output;
my $exit_status;

$output = output(
    sub { $exit_status = pt_table_checksum::main(@args) },
    stderr => 1,
);

is(
    $exit_status,
    0,
    "PT-1616 pt-table-cheksum before --resume with binary fields exit status",
) or diag("$exit_status\n", $output);

@args = ("--set-vars", "innodb_lock_wait_timeout=50", 
    "--ignore-databases", "mysql", "--no-check-binlog-format", 
    "--chunk-size", "1", 
    "--resume", "--run-time", "5s", $source_dsn
);

$output = output(
    sub { $exit_status = pt_table_checksum::main(@args) },
    stderr => 1,
);

is(
    $exit_status,
    0,
    "PT-1616 pt-table-cheksum --resume with binary fields exit status",
);

unlike(
    $output,
    qr/called with \d+ bind variables when \d+ are needed/,
    "PT-1616 pt-table-cheksum --resume parameters binding error",
) or die($output);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
