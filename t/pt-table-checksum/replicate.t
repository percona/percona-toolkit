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

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 10;
}

my $row;
my ($output, $output2);
my $cnf  = '/tmp/12345/my.sandbox.cnf';
my @args = ('-F', $cnf, qw(-d test -t checksum_test 127.0.0.1 --replicate test.checksum));

$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/replicate.sql');

sub empty_repl_tbl {
   $master_dbh->do('truncate table test.checksum');
   wait_until(
      sub {
         my @rows;
         eval {
            @rows = $master_dbh->selectall_array("select * from test.checksum");
         };
         return 1 if @rows == 0;
      },
   );
   ok(1, "Empty checksum table");
}

sub set_tx_isolation {
   my ( $level ) = @_;
   $master_dbh->do("set global transaction isolation level $level");
   $master_dbh->disconnect();
   $master_dbh = $sb->get_dbh_for('master');
   $row = $master_dbh->selectrow_arrayref("show variables like 'tx_isolation'");
   $level =~ s/ /-/g;
   $level = uc $level;
   is(
      $row->[1],
      $level,
      "Tx isolation $level"
   );
}

sub set_binlog_format {
   my ( $format ) = @_;
   $master_dbh->do("set global binlog_format=$format");
   $master_dbh->disconnect();
   $master_dbh = $sb->get_dbh_for('master');
   $row = $master_dbh->selectrow_arrayref("show variables like 'binlog_format'");
   $format = uc $format;
   is(
      $row->[1],
      $format,
      "Binlog format $format"
   );
}

# #############################################################################
# Test that --replicate disables --lock, --wait and --slave-lag like the
# docu says.  Once it didn't and that lead to issue 51.
# #############################################################################
my $cmd = "$trunk/bin/pt-table-checksum";

$output = `$cmd localhost --replicate test.checksum --help --wait 5`;
like(
   $output,
   qr/--lock\s+FALSE/,
   "--replicate disables --lock"
);

like(
   $output,
   qr/--slave-lag\s+FALSE/,
   "--replicate disables --slave-lag"
);

like(
   $output,
   qr/--wait\s+\(No value\)/,
   "--replicate disables --wait"
);


# #############################################################################
# Test basic --replicate functionality.
# #############################################################################

$output = output(
   sub { mk_table_checksum::main(@args, qw(--function sha1)) },
);
$output2 = `/tmp/12345/use --skip-column-names -e "select this_crc from test.checksum where tbl='checksum_test'"`;
my ($cnt, $crc) = $output =~ m/checksum_test *\d+ \S+ \S+ *(\d+|NULL) *(\w+)/;
chomp $output2;
is(
   $crc,
   $output2,
   'Write checksum to --replicate table'
);


# #############################################################################
# Issue 720: mk-table-checksum --replicate should set transaction isolation
# level
# #############################################################################
SKIP: {
   skip "binlog_format test for MySQL v5.1+", 6
      unless $sandbox_version gt '5.0';

   empty_repl_tbl();
   set_binlog_format('row');
   set_tx_isolation('read committed');

   $output = output(
      sub { mk_table_checksum::main(@args) },
      stderr   => 1,
   );
   like(
      $output,
      qr/test\s+checksum_test\s+0\s+127.0.0.1\s+MyISAM\s+1\s+83dcefb7/,
      "Set session transaction isolation level repeatable read"
   );

   set_binlog_format('statement');
   set_tx_isolation('repeatable read');
}

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
exit;
