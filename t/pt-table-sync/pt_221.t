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
require "$trunk/bin/pt-table-sync";

sub set_binlog_format {
    my ($sb, $format) = @_;

    my $source_dbh = $sb->get_dbh_for('source');
    my $replica1_dbh = $sb->get_dbh_for('replica1');
    my $replica2_dbh = $sb->get_dbh_for('replica2');
    
    $replica2_dbh->do("STOP ${replica_name}");
    $replica1_dbh->do("STOP ${replica_name}");
    
    $replica2_dbh->do("SET GLOBAL binlog_format='$format'");
    $replica1_dbh->do("SET GLOBAL binlog_format='$format'");
    $source_dbh->do("SET GLOBAL binlog_format='$format'");

    $replica2_dbh->do("START ${replica_name}");
    $replica1_dbh->do("START ${replica_name}");
}

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp, env => q/BINLOG_FORMAT="ROW"/);

my $source_dbh = $sb->get_dbh_for('source');
my $source_dsn = $sb->dsn_for('source');
my $replica_dsn  = $sb->dsn_for('replica1');


if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
} elsif ($sb->has_engine('source', 'rocksdb') != 1) {
   plan skip_all => 'This test needs RocksDB engine';
} else {
   plan tests => 4;
}

set_binlog_format($sb, 'ROW');

$source_dbh->disconnect();
$source_dbh = $sb->get_dbh_for('source');

$sb->load_file('source', 't/pt-table-sync/samples/pt_221.sql');

my @args = ('--sync-to-source', $replica_dsn, qw(-t test.t1 --print --execute));

my ($output, $exit) = full_output(
   sub { pt_table_sync::main(@args, qw()) },
   stderr => 1,
);

isnt(
    $exit,
    0,
    "PT-221 fails if using --sync-to-source with RocksDB",
);

like(
    $output,
    qr/Cannot sync using --sync-to-source with test.t1 due to the limitations of the RocksDB engine/,
    "PT-221 Cannot use --sync-to-source with RockSDB",
);

$sb->wait_for_replicas();

@args = ('--replicate', 'test.checksums', $source_dsn, qw(-t test.t1 --print --execute));

($output, $exit) = full_output(
   sub { pt_table_sync::main(@args, qw()) },
   stderr => 1,
);

is(
    $exit,
    0,
    "PT-221 Doesn't fail if using --replicate with RocksDB",
);

set_binlog_format($sb, 'STATEMENT');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);


ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
