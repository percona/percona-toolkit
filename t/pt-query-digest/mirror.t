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
use DSNParser;
use Sandbox;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');
my $dbh2 = $sb->get_dbh_for('slave1');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 3;
}

my $output;
my $cmd;

# ##########################################################################
# Tests for swapping --processlist and --execute
# ##########################################################################
$dbh1->do('set global read_only=0');
$dbh2->do('set global read_only=1');
$cmd  = "$trunk/bin/pt-query-digest "
         . "--processlist h=127.1,P=12345,u=msandbox,p=msandbox "
         . "--execute h=127.1,P=12346,u=msandbox,p=msandbox --mirror 1 "
         . "--pid foobar";
# --pid actually does nothing because the script is not daemonizing.
# I include it for the identifier (foobar) so that we can more easily
# grep the PID below. Otherwise, a ps | grep mk-query-digest will
# match this test script and any vi mk-query-digest[.t] that may happen
# to be running.

$ENV{MKDEBUG}=1;
`$cmd > /tmp/read_only.txt 2>&1 &`;
$ENV{MKDEBUG}=0;
sleep 5;
$dbh1->do('select sleep(1)');
sleep 1;
$dbh1->do('set global read_only=1');
$dbh2->do('set global read_only=0');
$dbh1->do('select sleep(1)');
sleep 2;
$output = `ps -eaf | grep mk-query-diges[t] | grep foobar | awk '{print \$2}'`;
kill 15, $output =~ m/(\d+)/g;
sleep 1;
# Verify that it's dead...
$output = `ps -eaf | grep mk-query-diges[t] | grep foobar`;
if ( $output =~ m/digest/ ) {
   $output = `ps -eaf | grep mk-query-diges[t] | grep foobar`;
}
unlike($output, qr/mk-query-digest/, 'It is stopped now'); 

$dbh1->do('set global read_only=0');
$dbh2->do('set global read_only=1');
$output = `grep read_only /tmp/read_only.txt`;
# Sample output:
# # main:3619 6897 read_only on execute for --execute: 1 (want 1)
# # main:3619 6897 read_only on processlist for --processlist: 0 (want 0)
# # main:3619 6897 read_only on processlist for --processlist: 0 (want 0)
# # main:3619 6897 read_only on processlist for --processlist: 0 (want 0)
# # main:3619 6897 read_only on processlist for --processlist: 0 (want 0)
# # main:3619 6897 read_only on processlist for --processlist: 0 (want 0)
# # main:3619 6897 read_only on processlist for --processlist: 0 (want 0)
# # main:3619 6897 read_only on execute for --execute: 0 (want 1)
# # main:3622 6897 read_only wrong for --execute getting a dbh from processlist
# # main:3619 6897 read_only on processlist for --processlist: 1 (want 0)
# # main:3622 6897 read_only wrong for --processlist getting a dbh from execute
# # main:3619 6897 read_only on processlist for --execute: 1 (want 1)
# # main:3619 6897 read_only on execute for --processlist: 0 (want 0)
like($output, qr/wrong for --execute getting a dbh from processlist/,
    'switching --processlist works');
like($output, qr/wrong for --processlist getting a dbh from execute/,
    'switching --execute works');

diag(`rm -rf /tmp/read_only.txt`);

# #############################################################################
# Done.
# #############################################################################
$dbh1->do('set global read_only=0');
$dbh2->do('set global read_only=1');
$sb->wipe_clean($dbh1);
exit;
