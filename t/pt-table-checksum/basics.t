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

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $vp = new VersionParser();
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 12;
}

my ($output, $output2);
my $cnf  ='/tmp/12345/my.sandbox.cnf';
my @args = ('-F', $cnf, qw(-d test -t checksum_test 127.0.0.1));

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/before.sql');

# Test basic functionality with defaults
$output = output(sub { mk_table_checksum::main(@args) } );
like($output, qr/^DATABASE/m, 'The header row is there');
like($output, qr/checksum_test/, 'The results row is there');

my ( $cnt, $crc ) = $output =~ m/checksum_test *\d+ \S+ \S+ *(\d+|NULL) *(\w+)/;
like($cnt, qr/1|NULL/, 'One row in the table, or no count');
if ( $output =~ m/cannot be used; using MD5/ ) {
   # same as md5(md5(1))
   is($crc, '28c8edde3d61a0411511d3b1866f0636', 'MD5 is okay');
}
elsif ( $crc =~ m/^\d+$/ ) {
   is($crc, 3036305396, 'CHECKSUM is okay');
}
else {
   # same as sha1(sha1(1))
   is($crc, '9c1c01dc3ac1445a500251fc34a15d3e75a849df', 'SHA1 is okay');
}

# Test that it works with locking
$output = output(
   sub { mk_table_checksum::main(@args, qw(--lock --slave-lag),
         qw(--function sha1 --checksum --algorithm ACCUM)) }
);
like($output, qr/9c1c01dc3ac1445a500251fc34a15d3e75a849df/, 'Locks' );

SKIP: {
   skip 'MySQL version < 4.1', 5
      unless $vp->version_ge($master_dbh, '4.1.0');

   $output = output(
      sub { mk_table_checksum::main(@args,
         qw(--function CRC32 --checksum --algorithm ACCUM)) }
   );
   like($output, qr/00000001E9F5DC8E/, 'CRC32 ACCUM' );

   $output = output(
      sub { mk_table_checksum::main(@args,
         qw(--function sha1 --checksum --algorithm ACCUM)) }
   );
   like($output, qr/9c1c01dc3ac1445a500251fc34a15d3e75a849df/, 'SHA1 ACCUM' );

   # same as sha1(1)
   $output = output(
      sub { mk_table_checksum::main(@args,
         qw(--function sha1 --checksum --algorithm BIT_XOR)) }
   );
   like($output, qr/356a192b7913b04c54574d18c28d46e6395428ab/, 'SHA1 BIT_XOR' );

   # test that I get the same result with --no-optxor
   $output2 = output(
      sub { mk_table_checksum::main(@args,
         qw(--function sha1 --no-optimize-xor --checksum --algorithm BIT_XOR)) }
   );
   is($output, $output2, 'Same result with --no-optxor');

   # same as sha1(1)
   $output = output(
      sub { mk_table_checksum::main(@args,
         qw(--checksum --function MD5 --algorithm BIT_XOR)) }
   );
   like($output, qr/c4ca4238a0b923820dcc509a6f75849b/, 'MD5 BIT_XOR' );
};

$output = output(
   sub { mk_table_checksum::main(@args, 
      qw(--checksum --function MD5 --algorithm ACCUM)) }
);
like($output, qr/28c8edde3d61a0411511d3b1866f0636/, 'MD5 ACCUM' );


# ############################################################################
# --sleep
# ############################################################################

# Issue 1256: mk-tabe-checksum: if no rows are found in a chunk, don't perform the sleep
my $t0 = time;
output(
   sub { mk_table_checksum::main("F=$cnf",
      qw(--sleep 5 -t mysql.user --chunk-size 100)) },
);
ok(
   time - $t0 < 1,
   "--sleep doesn't sleep unless table is chunked"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
