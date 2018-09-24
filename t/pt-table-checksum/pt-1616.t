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
    plan tests => 4;
}

diag("loading samples");
$sb->load_file('master', 't/pt-table-checksum/samples/pt-1616.sql');

my $num_rows = 50000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox junk pt_test_100 $num_rows`);

# Insert invalid UTF-8 chars
#diag(">>>1");
eval {
    $dbh->do("INSERT INTO junk.pt_test_100 (id1, id2) VALUES(unhex('F96DD7'), unhex('F96DD7'))");
};
die $EVAL_ERROR if ($EVAL_ERROR);
#
#diag(">>>2");
#Make checksums table support binary strings
$dbh->do('ALTER TABLE percona.checksums MODIFY upper_boundary BLOB, MODIFY lower_boundary BLOB;');
#diag(">>>3");

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = $sb->dsn_for('master');

my @args = ($master_dsn, "--set-vars", "innodb_lock_wait_timeout=50", 
    "--ignore-databases", "mysql", "--no-check-binlog-format", 
    "--chunk-size", "1", 
    "--empty-replicate-table", "--run-time", "2s"
);
#diag(join(" ", @args));

my $output;
my $exit_status;

#diag(">>>3.1");
# Test #1 
$output = output(
    sub { $exit_status = pt_table_checksum::main(@args) },
    stderr => 1,
);

is(
    $exit_status,
    0,
    "PT-1616 pt-table-cheksum before --resume with binary fields exit status",
);

#diag($output);
#diag($exit_status);

# Once checksum stops, insert an entry in percona.checksums table to make it resume from bad entry
#diag(">>>4");
my $row = $dbh->selectcol_arrayref("SELECT MAX(chunk) FROM percona.checksums WHERE tbl='pt_test_100'");
#diag(">>>4.1: ". $row->[0]);
my $query = "REPLACE INTO percona.checksums (db, tbl, chunk, chunk_index, lower_boundary, ".
            "upper_boundary, this_crc, this_cnt, master_crc, master_cnt) VALUES ".
            "('junk', 'pt_test_100', ". $row->[0]. ", 'PRIMARY', unhex('F96DD72CF96DD7'), ".
            "unhex('F96DD72CF96DD7'), 'crc', 1, 'crc', 1) ";
#diag(">>>5");
eval {
    $dbh->do($query);
};
#diag($EVAL_ERROR) if $EVAL_ERROR;

#diag(">>>6");

@args = ("--set-vars", "innodb_lock_wait_timeout=50", 
    "--ignore-databases", "mysql", "--no-check-binlog-format", 
    "--chunk-size", "1", 
    "--resume", "--run-time", "5s", $master_dsn
);
#diag("Running test 1: \nbin/pt-table-checksum ".join(" ", @args) );
$output = output(
    sub { $exit_status = pt_table_checksum::main(@args) },
    stderr => 1,
);
# my $cmd = "$trunk/bin/pt-table-checksum $master_dsn ".join(" ", @args);
# eval {
#     $output = `$cmd &2>1`;
# };
#diag(">>>7");
#diag($output);
#diag($exit_status);

is(
    $exit_status,
    0,
    "PT-1616 pt-table-cheksum --resume with binary fields exit status",
);

unlike(
    $output,
    qr/called with 2 bind variables when 3 are needed/,
    "PT-1616 pt-table-cheksum --resume parameters binding error",
);


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
