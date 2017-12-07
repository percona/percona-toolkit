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

use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir /;

plan tests => 2;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

our ($master_dbh, $master_dsn) = $sb->start_sandbox(
	server => 'master',
	type   => 'master',
	env    => q/FORK="pxc" BINLOG_FORMAT="ROW"/,
);

if ( !$master_dbh ) {
	plan skip_all => 'Cannot connect to sandbox master';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

$sb->load_file('master', "$sample/pt-229.sql");
diag(`util/mysql_random_data_load_linux_amd64 --host=127.1 --port=12345 --user=msandbox --password=msandbox test test_a 400000`);

my $threads = [];

sub signal_handler {
    my $i=0;
    for my $thread (@$threads) {
        $i++;
        diag ("Signaling thread #$i to stop");
        $thread->kill("STOP");
        $thread->join();
        diag ("Thread $i stopped");
    }
}

sub start_thread {
	my ($dsn_opts, $node) = @_;

	my $stop;
	$SIG{'STOP'} = sub { 
		$stop = 1;
	};

	my $dp = new DSNParser(opts=>$dsn_opts);
	my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
	my $dbh= $sb->get_dbh_for($node);
	diag("Thread started");

	while(!$stop) {
	    $dbh->do("UPDATE `test`.`test_a` SET modified=NOW() WHERE RAND() <= 0.2 LIMIT 1");
		my $random_sleep_time = rand() / 10;
		# diag("Row updated on node: $node. Sleeping $random_sleep_time");
		select(undef, undef, undef, $random_sleep_time);
	}
    print "leaving thread for $node\n";
}

#$SIG{INT} = \&signal_handler;

my $nodes = ['node1', 'node2', 'node3'];

for my $node (@$nodes) {
	my $thread = threads->create('start_thread', $dsn_opts, $node);
	$thread->detach();
	push @$threads, $thread;
}

threads->yield();

diag("Starting osc. A row will be updated in a different thread.");
($output, $exit_status) = full_output(
	sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=test_a",
			'--execute', 
			'--alter', "ADD COLUMN zzz INT",
		),
	},
    stderr => 1,
);
diag("status: $exit_status");
diag($output);

like(
	$output,
	qr/Successfully altered/s,
	"OK",
);

sleep(10);
threads->exit();

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
#$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
