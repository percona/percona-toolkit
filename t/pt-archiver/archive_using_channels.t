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
require "$trunk/bin/pt-archiver";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1'); 

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
} elsif ($sandbox_version lt '5.7') {
   plan skip_all => 'Only on MySQL 5.7+';
} else {
   plan tests => 4;
}

my ($master1_dbh, $master1_dsn) = $sb->start_sandbox(
   server => 'chan_master1',
   type   => 'master',
);
my ($master2_dbh, $master2_dsn) = $sb->start_sandbox(
   server => 'chan_master2',
   type   => 'master',
);
my ($slave1_dbh, $slave1_dsn) = $sb->start_sandbox(
   server => 'chan_slave1',
   type   => 'master',
);
my $slave1_port = $sb->port_for('chan_slave1');

$sb->load_file('chan_master1', "sandbox/gtid_on.sql", undef, no_wait => 1);
$sb->load_file('chan_master2', "sandbox/gtid_on.sql", undef, no_wait => 1);
$sb->load_file('chan_slave1', "sandbox/slave_channels.sql", undef, no_wait => 1);

my $master1_port = $sb->port_for('chan_master1');
my $num_rows = 40000;

# Load some rows into masters 1 & 2.
$sb->load_file('chan_master1', "t/pt-archiver/samples/channels.sql", undef, no_wait => 1);

diag("Loading $num_rows into the test.t1 table on first master. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=$master1_port --user=msandbox --password=msandbox test t1 $num_rows`);
diag("$num_rows rows loaded. Starting tests.");
$master_dbh->do("FLUSH TABLES");

my $rows = $master1_dbh->selectrow_arrayref('SELECT COUNT(*) FROM test.t1 ');

is(
    @$rows[0],
    $num_rows,
    "All rows were loaded into master 1",
);

my @args = ('--source', $master1_dsn.',D=test,t=t1', '--purge', '--where', sprintf('id >= %d', $num_rows / 2), '--check-slave-lag', $slave1_dsn);

my ($exit_status, $output);

$output = output(
   sub { $exit_status = pt_archiver::main(@args) },
   stderr => 1,
);
is(
    $exit_status,
    0,
    'No need of channel name since there is only one master',
);

push @args, ('--channel', 'masterchan1');

output(
   sub { $exit_status = pt_archiver::main(@args, '--channel', 'masterchan1') },
   stderr => 1,
);

is(
    $exit_status,
    0,
    'Ok if channel name was specified',
);

$sb->stop_sandbox(qw(chan_master1 chan_master2 chan_slave1));


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
