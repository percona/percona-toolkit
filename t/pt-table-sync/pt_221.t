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

    my $master_dbh = $sb->get_dbh_for('master');
    my $slave1_dbh = $sb->get_dbh_for('slave1');
    my $slave2_dbh = $sb->get_dbh_for('slave2');
    
    $slave2_dbh->do("STOP SLAVE");
    $slave1_dbh->do("STOP SLAVE");
    
    $slave2_dbh->do("SET GLOBAL binlog_format='$format'");
    $slave1_dbh->do("SET GLOBAL binlog_format='$format'");
    $master_dbh->do("SET GLOBAL binlog_format='$format'");

    $slave2_dbh->do("START SLAVE");
    $slave1_dbh->do("START SLAVE");
}

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp, env => q/BINLOG_FORMAT="ROW"/);

my $master_dbh = $sb->get_dbh_for('master');
my $master_dsn = $sb->dsn_for('master');
my $slave_dsn  = $sb->dsn_for('slave1');


if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
} elsif ($sb->has_engine('master', 'rocksdb') != 1) {
   plan skip_all => 'This test needs RocksDB engine';
} else {
   plan tests => 4;
}

set_binlog_format($sb, 'ROW');

$master_dbh->disconnect();
$master_dbh = $sb->get_dbh_for('master');

$sb->load_file('master', 't/pt-table-sync/samples/pt_221.sql');

my @args = ('--sync-to-master', $slave_dsn, qw(-t test.t1 --print --execute));

my ($output, $exit) = full_output(
   sub { pt_table_sync::main(@args, qw()) },
   stderr => 1,
);

isnt(
    $exit,
    0,
    "PT-221 fails if using --sync-to-master with RocksDB",
);

like(
    $output,
    qr/Cannot sync using --sync-to-master with test.t1 due to the limitations of the RocksDB engine/,
    "PT-221 Cannot use --sync-to-master with RockSDB",
);

$sb->wait_for_slaves();

@args = ('--replicate', 'test.checksums', $master_dsn, qw(-t test.t1 --print --execute));

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
$sb->wipe_clean($master_dbh);


ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
