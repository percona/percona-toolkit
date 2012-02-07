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
my $pid_file = "/tmp/pt-query-digest-mirror-test.pid";

diag(`rm $pid_file 2>/dev/null`);

# ##########################################################################
# Tests for swapping --processlist and --execute
# ##########################################################################
$dbh1->do('set global read_only=0');
$dbh2->do('set global read_only=1');
$cmd  = "$trunk/bin/pt-query-digest "
         . "--processlist h=127.1,P=12345,u=msandbox,p=msandbox "
         . "--execute h=127.1,P=12346,u=msandbox,p=msandbox --mirror 1 "
         . "--pid $pid_file";

$ENV{PTDEBUG}=1;
`$cmd > /tmp/read_only.txt 2>&1 &`;
$ENV{PTDEBUG}=0;
sleep 5;
$dbh1->do('select sleep(1)');
sleep 1;
$dbh1->do('set global read_only=1');
$dbh2->do('set global read_only=0');
$dbh1->do('select sleep(1)');
sleep 2;
chomp($output = `cat $pid_file`);
kill 15, $output;
sleep 1;
# Verify that it's dead...
$output = `ps -p $output`;
unlike($output, qr/pt-query-digest/, 'It is stopped now'); 

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
diag(`rm $pid_file 2>/dev/null`);
$dbh1->do('set global read_only=0');
$dbh2->do('set global read_only=1');
$sb->wipe_clean($dbh1);
exit;
