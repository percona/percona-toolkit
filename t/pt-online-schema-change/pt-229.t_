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

plan tests => 5;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $master_dbh = $sb->get_dbh_for('node1');
my $master_dsn = $sb->dsn_for('node1');

if ( !$master_dbh ) {
    plan skip_all => 'Cannot connect to sandbox master';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;

$sb->load_file('master', "t/pt-online-schema-change/samples/pt-229.sql");

my $num_rows = 40000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test test_a $num_rows`);
diag("$num_rows rows loaded. Starting tests.");
$master_dbh->do("FLUSH TABLES");

my $threads = [];

sub signal_handler {
    my $i=0;
    for my $thread (@$threads) {
        $i++;
        diag ("Signaling thread #$i to stop");
        $thread->kill("STOP");
    }
}

sub start_thread {
    my ($dsn_opts, $node, $s) = @_;

    my $stop;
    $SIG{'STOP'} = sub { 
        $stop = 1;
    };

    my $dp = new DSNParser(opts=>$dsn_opts);
    my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
    my $dbh= $sb->get_dbh_for($node);
    diag("Thread started");

    while(!$stop) {
        eval {
            $dbh->do("UPDATE `test`.`test_a` SET modified=NOW() WHERE RAND() <= 0.2 LIMIT 1");
        };
        my $random_sleep_time = rand() / 10;
        select(undef, undef, undef, $random_sleep_time);
    }
    print "Thread for $node has been stopped\n";
    $s->up();
}

$SIG{INT} = \&signal_handler;

my $nodes = ['node1', 'node2', 'node3'];

my $s = Thread::Semaphore->new();

for my $node (@$nodes) {
    my $thread = threads->create('start_thread', $dsn_opts, $node, $s);
    $thread->detach();
    push @$threads, $thread;
}

threads->yield();

diag("Starting osc. Random rows will be updated in other threads.");
($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=test_a",
            '--execute', 
            '--alter', "ADD COLUMN zzz INT",
        ),
    },
    stderr => 1,
);

is(
    $exit_status,
    0,
    "PT-229 Successfully altered. Exit status = 0",
);

like(
    $output,
    qr/Successfully altered/s,
    "PT-229 Got successfully altered message.",
);

my $rows = $master_dbh->selectrow_arrayref('SHOW CREATE TABLE test.test_a');
like(
    @$rows[1],
    qr/  `zzz` int\(11\) DEFAULT NULL,/im,
    "PT-229 New field was added",
);

$rows = $master_dbh->selectrow_arrayref('SELECT COUNT(*) FROM test.test_a');
is(
    @$rows[0],
    $num_rows,
    "PT-229 Number of rows is correct",
);

signal_handler(); # Signal all threads to stop

for (@$threads) {
    $s->down(); # Wait until all threads are really stopped
}

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
