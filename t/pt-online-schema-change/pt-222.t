#!/usr/bin/env perl

BEGIN {
    die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
    unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
    unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;

use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir /;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';

if ( !$master_dbh ) {
    plan skip_all => 'Cannot connect to sandbox master';
} elsif ($sandbox_version lt '5.7') {
    plan skip_all => "RocksDB is only available on Percona Server 5.7.19+";
} elsif (!$sb->has_engine('master', 'rocksdb')) {
    plan skip_all => "RocksDB engine is not available";
} else {
    plan tests => 3;
}

$master_dbh->disconnect();
$master_dbh = $sb->get_dbh_for('master');

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";


$sb->load_file('master', "$sample/pt-209.sql");

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=t1",
            '--execute', 
            '--alter', "ADD COLUMN c1 INT",
        ),
    },
);

isnt(
    $exit_status,
    0,
    "PT-222 Altering RocksDB is not supported exit status != 0",
);

like(
    $output,
    qr/The RocksDB storage engine is not supported with pt-online-schema-change since RocksDB does not support gap locks/s,
    "PT-222 RocksDB is not supported",
);

$master_dbh->disconnect();
$master_dbh = $sb->get_dbh_for('master');
$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;
