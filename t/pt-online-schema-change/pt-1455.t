#!/usr/bin/env perl

BEGIN {
    die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
    unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
    unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;
use threads::shared;
use Thread::Semaphore;

use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir /;

plan tests => 4;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $master_dbh = $sb->get_dbh_for("master");
my $master_dsn = $sb->dsn_for("master");

my $slave1_dbh = $sb->get_dbh_for("slave1");
my $slave1_dsn = $sb->dsn_for("slave1");

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;

# $sb->load_file('master3', "t/pt-online-schema-change/samples/pt-244.sql");
$slave1_dbh->do("STOP SLAVE");
$slave1_dbh->do("CHANGE REPLICATION FILTER REPLICATE_IGNORE_DB = (ignored_db)");
$slave1_dbh->do("START SLAVE");

$master_dbh->do("DROP DATABASE IF EXISTS ignored_db");
$master_dbh->do("CREATE DATABASE ignored_db");
$master_dbh->do("CREATE TABLE ignored_db.t1 (id int, f2 int) ENGINE=InnoDB");

my $num_rows = 1000;
my $master_port = $Sandbox::port_for{master};

diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load_linux_amd64 --host=127.1 --port=$master_port --user=msandbox --password=msandbox test t3 $num_rows`);
diag("$num_rows rows loaded. Starting tests.");

$master_dbh->do("FLUSH TABLES");

my $new_dir='/tmp/tdir';
diag(`rm -rf $new_dir`);
diag(`mkdir $new_dir`);

diag("2");
($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=t3",
            '--execute', 
            '--alter', "engine=innodb",
            '--data-dir', $new_dir,
        ),
    },
    stderr => 1,
);
diag("3");

is(
    $exit_status,
    0,
    "PT-244 Successfully altered. Exit status = 0",
);

like(
    $output,
    qr/Successfully altered/s,
    "PT-244 Got successfully altered message.",
);


my $db_dir="$new_dir/test/";
opendir(my $dh, $db_dir) || die "Can't opendir $db_dir: $!";
my @files = grep { /^t3#P#p/  } readdir($dh);
closedir $dh;

is(
    scalar @files,
    4,
    "PT-224 Number of files is correct",
);

$dbh3->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh3);
diag(`$trunk/sandbox/stop-sandbox $master3_port >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
