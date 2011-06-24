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

my $vp  = new VersionParser();
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

my $output;
my $cnf  = '/tmp/12345/my.sandbox.cnf';
my @args = ('-F', $cnf, 'h=127.1', qw(--replicate test.checksums --create-replicate-table -t sakila.city));

$sb->create_dbs($dbh, ['test']);

$dbh->do('use sakila');
$dbh->do('begin');
$dbh->do('select * from city for update');

# city table is now locked until we commit.  The child proc is going
# to wait 3 seconds for innodb_lock_wait_timeout, then it should try
# again.  So if we commit at 4 seconds, the child should succeed and
# the checksum will appear in test.checksums.

my $pid = fork();
if ( !$pid ) {
   # child
   my $output = output(
      sub { mk_table_checksum::main(@args) },
      stderr => 1,
   );
   exit 0;
}

sleep 4;
$dbh->do('commit');

waitpid ($pid, 0);  # reap child

my $row = $dbh->selectrow_hashref('select * from test.checksums');
ok(
   $row && $row->{db} eq 'sakila' && $row->{tbl} eq 'city',
   "Checksum after lock wait timeout"
);


# Repeat the test but this time let the retry fail to see that the
# failure is captured.
my $outfile = '/tmp/mk-table-checksum-output.txt';
diag(`rm -rf $outfile >/dev/null`);

$dbh->do('truncate table test.checksums');

$dbh->do('begin');
$dbh->do('select * from city for update');

$pid = fork();
if ( !$pid ) {
   # child
   my $output = output(
      sub { mk_table_checksum::main(@args) },
      stderr => 1,
      file   => $outfile,
   );
   exit 0;
}

sleep 8;
$dbh->do('commit');

waitpid ($pid, 0);  # reap child

$row = $dbh->selectrow_hashref('select * from test.checksums');
ok(
   !defined $row,
   "No checksum due to lock wait timeout"
);

$output = `cat $outfile`;
like(
   $output,
   qr/Lock wait timeout exceeded/i,
   "Lock wait timeout exceeded error captured"
);

diag(`rm -rf $outfile >/dev/null`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
