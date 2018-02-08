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

$sb->load_file('slave1', "t/pt-online-schema-change/samples/pt-1455_slave.sql");
$sb->load_file('slave2', "t/pt-online-schema-change/samples/pt-1455_slave.sql");
$sb->load_file('master', "t/pt-online-schema-change/samples/pt-1455_master.sql");

my $num_rows = 1000;
my $master_port = $Sandbox::port_for{master};

diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load_linux_amd64 --host=127.1 --port=$master_port --user=msandbox --password=msandbox ignored_db t1 $num_rows`);
diag("$num_rows rows loaded. Starting tests.");

$master_dbh->do("FLUSH TABLES");

my $new_dir='/tmp/tdir';
diag(`rm -rf $new_dir`);
diag(`mkdir $new_dir`);

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$master_dsn,D=ignored_db,t=t1",
            '--execute', 
            '--alter', "engine=innodb",
        ),
    },
    stderr => 1,
);

is(
    $exit_status,
    0,
    "PT-1455 Successfully altered. Exit status = 0",
);

like(
    $output,
    qr/Successfully altered/s,
    "PT-1455 Got successfully altered message.",
);


my $db_dir="$new_dir/test/";
opendir(my $dh, $db_dir) || die "Can't opendir $db_dir: $!";
my @files = grep { /^t3#P#p/  } readdir($dh);
closedir $dh;

is(
    scalar @files,
    4,
    "PT-1455 Number of files is correct",
);

$master_dbh->do("DROP DATABASE IF EXISTS ignored_db");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
