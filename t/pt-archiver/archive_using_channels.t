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
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1'); 

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
} elsif ($sandbox_version lt '5.7') {
   plan skip_all => 'Only on MySQL 5.7+';
} else {
   plan tests => 8;
}

my ($source1_dbh, $source1_dsn) = $sb->start_sandbox(
   server => 'chan_source1',
   type   => 'source',
);
my ($source2_dbh, $source2_dsn) = $sb->start_sandbox(
   server => 'chan_source2',
   type   => 'source',
);
my ($replica1_dbh, $replica1_dsn) = $sb->start_sandbox(
   server => 'chan_replica1',
   type   => 'source',
);
my $replica1_port = $sb->port_for('chan_replica1');

if ( $sandbox_version lt '8.1' ) {
   $sb->load_file('chan_source1', "sandbox/gtid_on-legacy.sql", undef, no_wait => 1);
   $sb->load_file('chan_source2', "sandbox/gtid_on-legacy.sql", undef, no_wait => 1);
   $sb->load_file('chan_replica1', "sandbox/replica_channels-legacy.sql", undef, no_wait => 1);
} else {
   $sb->load_file('chan_source1', "sandbox/gtid_on.sql", undef, no_wait => 1);
   $sb->load_file('chan_source2', "sandbox/gtid_on.sql", undef, no_wait => 1);
   $sb->load_file('chan_replica1', "sandbox/replica_channels.sql", undef, no_wait => 1);
}

my $source1_port = $sb->port_for('chan_source1');
my $num_rows = 40000;

# Load some rows into sources 1 & 2.
$sb->load_file('chan_source1', "t/pt-archiver/samples/channels.sql", undef, no_wait => 1);

diag("Loading $num_rows into the test.t1 table on first source. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=$source1_port --user=msandbox --password=msandbox test t1 $num_rows`);
diag("$num_rows rows loaded. Starting tests.");
$source_dbh->do("FLUSH TABLES");

my $rows = $source1_dbh->selectrow_arrayref('SELECT COUNT(*) FROM test.t1 ');

is(
    @$rows[0],
    $num_rows,
    "All rows were loaded into source 1",
);

my @args = ('--source', $source1_dsn.',D=test,t=t1', '--purge', '--where', sprintf('id >= %d', $num_rows / 2), "--check-replica-lag", $replica1_dsn);

my ($exit_status, $output);

$output = output(
   sub { $exit_status = pt_archiver::main(@args) },
   stderr => 1,
);

isnt(
    $exit_status,
    0,
    'Must specify a channel name',
);

like (
    $output,
    qr/"channel" was not specified/,
    'Message saying channel name must be specified'
) or diag($output);

# Legacy option --check-slave-lag
@args = ('--source', $source1_dsn.',D=test,t=t1', '--purge', '--where', sprintf('id >= %d', $num_rows / 2), "--check-slave-lag", $replica1_dsn);

$output = output(
   sub { $exit_status = pt_archiver::main(@args) },
   stderr => 1,
);

isnt(
    $exit_status,
    0,
    'Must specify a channel name',
);

like (
    $output,
    qr/"channel" was not specified/,
    'Message saying channel name must be specified'
) or diag($output);

like(
   $output,
   qr/Option --check-slave-lag is deprecated and will be removed in future versions./,
   'Deprecation warning printed'
) or diag($output);

push @args, ('--channel', 'sourcechan1');

output(
   sub { $exit_status = pt_archiver::main(@args, '--channel', 'sourcechan1') },
   stderr => 1,
);

is(
    $exit_status,
    0,
    'Ok if channel name was specified',
);

$sb->stop_sandbox(qw(chan_source1 chan_source2 chan_replica1));


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
