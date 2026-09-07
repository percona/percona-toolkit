#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use Test::More;
use File::Temp qw(tempfile);

use PerconaTest;
use Sandbox;

require "$trunk/bin/pt-online-schema-change";

my $delay = 8;

my $dp = new DSNParser(opts => $dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
elsif ( $sb->is_cluster_mode ) {
   plan skip_all => 'Not for PXC';
}

my $source_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $replica_dsn = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';
my $pause_file = '/tmp/pt-2531.pause';
unlink $pause_file;

$source_dbh->do('CREATE DATABASE IF NOT EXISTS test');
$source_dbh->do('DROP TABLE IF EXISTS test.pt_2531_replicas');
$source_dbh->do('DROP TABLE IF EXISTS test.pt_2531');
$source_dbh->do('CREATE TABLE test.pt_2531 (id INTEGER NOT NULL AUTO_INCREMENT, value INTEGER NOT NULL, PRIMARY KEY (id))');
$source_dbh->do('CREATE TABLE test.pt_2531_replicas (id INTEGER PRIMARY KEY, dsn VARCHAR(255))');
$source_dbh->do("INSERT INTO test.pt_2531_replicas (id, dsn) VALUES (1, '$replica_dsn')");
$source_dbh->do('INSERT INTO test.pt_2531 (value) VALUES (1)');
for ( 1 .. 8 ) {
   $source_dbh->do('INSERT INTO test.pt_2531 (value) SELECT value FROM test.pt_2531');
}
$sb->wait_for_replicas();

$replica_dbh->do("STOP ${replica_name}");
$replica_dbh->do("CHANGE ${source_change} TO ${source_name}_DELAY=$delay");
$replica_dbh->do("START ${replica_name}");
$source_dbh->do('UPDATE test.pt_2531 SET value = value + 1 WHERE id = 1');
sleep($delay / 4);

my ($output_fh, $output_file) = tempfile();
my $args = "$source_dsn,D=test,t=pt_2531 --execute --alter 'ADD COLUMN copied INTEGER NULL' "
   . "--chunk-size 1 --chunk-time 0 --max-lag 0 --check-interval 1 "
   . "--recursion-method=dsn=D=test,t=pt_2531_replicas --progress time,60";
my $pid = fork();
die 'Cannot fork pt-online-schema-change' unless defined $pid;

if ( !$pid ) {
   open(STDERR, '>', $output_file);
   open(STDOUT, '>', $output_file);
   exec("$trunk/bin/pt-online-schema-change $args");
}

my ($initial_sleeping_connections) = $replica_dbh->selectrow_array(
   q{SELECT COUNT(*) FROM information_schema.processlist WHERE USER = 'msandbox' AND COMMAND = 'Sleep'}
);

sleep(10);
my ($sleeping_connections) = $replica_dbh->selectrow_array(
   q{SELECT COUNT(*) FROM information_schema.processlist WHERE USER = 'msandbox' AND COMMAND = 'Sleep'}
);

is(
   $sleeping_connections - $initial_sleeping_connections,
   1,
   'DSN-table refreshes keep only one sleeping connection on the replica',
);

waitpid($pid, 0);
my $output = do {
   local $/ = undef;
   <$output_fh>;
};
close $output_fh;
unlink $output_file;

like($output, qr/Successfully altered `test`.`pt_2531`/s, 'pt-online-schema-change completed');

$replica_dbh->do("STOP ${replica_name}");
$replica_dbh->do("CHANGE ${source_change} TO ${source_name}_DELAY=0");
$replica_dbh->do("START ${replica_name}");
$sb->wait_for_replicas();
$sb->wipe_clean($source_dbh);
ok($sb->ok(), 'Sandbox servers') or BAIL_OUT(__FILE__ . ' broke the sandbox');
done_testing;