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
else {
   plan tests => 6;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 

$sb->create_dbs($master_dbh, ['test']);
$sb->load_file('master', "t/lib/samples/char-chunking/ascii.sql", 'test');
#1
ok(
   no_diff(
      sub { pt_table_checksum::main(@args,
         qw(--tables test.ascii --chunk-index c --chunk-size 20),
         qw(--explain --explain)) },
      "t/pt-table-checksum/samples/char-chunk-ascii-explain.txt",
   ),
   "Char chunk ascii, explain"
);
#2
ok(
   no_diff(
      sub { pt_table_checksum::main(@args,
         qw(--tables test.ascii --chunk-index c --chunk-size 20),
         qw(--chunk-time 0)) },
      "t/pt-table-checksum/samples/char-chunk-ascii.txt",
      post_pipe => 'awk \'{print $2 " " $3 " " $4 " " $6 " " $7 " " $9}\'',
   ),
   "Char chunk ascii, chunk size 20"
);

my $row = $master_dbh->selectrow_arrayref("select lower_boundary, upper_boundary from percona.checksums where db='test' and tbl='ascii' and chunk=1");
is_deeply(
   $row,
   [ '', 'burt' ],
   "First boundaries"
);

$row = $master_dbh->selectrow_arrayref("select lower_boundary, upper_boundary from percona.checksums where db='test' and tbl='ascii' and chunk=9");
is_deeply(
   $row,
   [ undef, '' ],
   "Lower oob boundary"
);

$row = $master_dbh->selectrow_arrayref("select lower_boundary, upper_boundary from percona.checksums where db='test' and tbl='ascii' and chunk=10");
is_deeply(
   $row,
   [ 'ZESUS!!!', undef ],
   "Upper oob boundary"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
