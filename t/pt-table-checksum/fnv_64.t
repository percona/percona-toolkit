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
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-table-checksum -F $cnf -d test -t checksum_test 127.0.0.1";

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/before.sql');

eval { $master_dbh->do('DROP FUNCTION test.fnv_64'); };
eval { $master_dbh->do("CREATE FUNCTION fnv_64 RETURNS INTEGER SONAME 'fnv_udf.so';"); };
if ( $EVAL_ERROR ) {
   chomp $EVAL_ERROR;
   plan skip_all => "Failed to created FNV_64 UDF: $EVAL_ERROR";
}
else {
   plan tests => 5;
}

$output = `/tmp/12345/use -N -e 'select fnv_64(1)' 2>&1`;
is($output + 0, -6320923009900088257, 'FNV_64(1)');

$output = `/tmp/12345/use -N -e 'select fnv_64("hello, world")' 2>&1`;
is($output + 0, 6062351191941526764, 'FNV_64(hello, world)');

$output = `$cmd --function FNV_64 --checksum --algorithm ACCUM 2>&1`;
like($output, qr/DD2CD41DB91F2EAE/, 'FNV_64 ACCUM' );

$output = `$cmd --function CRC32 --checksum --algorithm BIT_XOR 2>&1`;
like($output, qr/83dcefb7/, 'CRC32 BIT_XOR' );

$output = `$cmd --function FNV_64 --checksum --algorithm BIT_XOR 2>&1`;
like($output, qr/a84792031e4ff43f/, 'FNV_64 BIT_XOR' );

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
