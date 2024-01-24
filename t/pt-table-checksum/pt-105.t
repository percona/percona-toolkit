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
use SqlModes;
use threads;
use Time::HiRes qw( usleep );
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

my $db_count = 100;

sub start_thread {
   my ($dsn_opts, $initial_sleep_time, $sleep_time, $db_count) = @_;
   my $dp = new DSNParser(opts=>$dsn_opts);
   my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
   my $dbh = $sb->get_dbh_for('master');
   PTDEBUG && diag("Thread started: Sleeping $initial_sleep_time milliseconds before start dropping DBs");
   usleep($initial_sleep_time );
   for (my $i=0; $i < $db_count; $i++) {
       PTDEBUG && diag("Dropping drop_test_$i");
       $dbh->do("DROP DATABASE IF EXISTS drop_test_$i");
       usleep($sleep_time * 1000)
   }
   PTDEBUG && diag("Exit thread")
}
my $thr = threads->create('start_thread', $dsn_opts, 1000, 100, $db_count);
threads->yield();

sleep(3);
for (my $i=0; $i < $db_count; $i++) {
    $dbh->do("DROP DATABASE IF EXISTS drop_test_$i");
    $dbh->do("CREATE SCHEMA drop_test_$i")
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--no-check-binlog-format)); 
my $output;

$output = output(
   sub { pt_table_checksum::main(@args) },
   stderr => 1,
);

unlike(
   $output,
   qr/db selectall_arrayref failed/,
   "Dropping tables while checksum is running"
);

$thr->join();

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
