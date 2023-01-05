#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;
use English qw(-no_match_vars);
use Test::More;
use Time::HiRes qw(sleep);

use PerconaTest;
use DSNParser;
use Sandbox;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $cnf      = "/tmp/12345/my.sandbox.cnf";
my $replicacnf = "/tmp/12346/my.sandbox.cnf";
my $pid_file = "/tmp/pt-stalk.pid.$PID";
my $log_file = "/tmp/pt-stalk.log.$PID";
my $dest     = "/tmp/pt-stalk.collect.$PID";
my $int_file = "/tmp/pt-stalk-after-interval-sleep";
my $pid;

sub cleanup {
   diag(`rm $pid_file $log_file $int_file 2>/dev/null`);
   diag(`rm -rf $dest 2>/dev/null`);
}

sub wait_n_cycles {
   my ($n) = @_;
   PerconaTest::wait_until(
      sub {
         return 0 unless -f "$dest/after_interval_sleep";
         my $n_cycles = `wc -l "$dest/after_interval_sleep"  | awk '{print \$1}'`;
         $n_cycles ||= '';
         chomp($n_cycles);
         return ($n_cycles || 0) >= $n; 
      },
      1.5,
      15
   );
}

# ###########################################################################
# Test that SHOW SLAVE STATUS outputs are captured
# ###########################################################################

my $retval = system("$trunk/bin/pt-stalk --no-stalk --run-time 1 --dest $dest --prefix nostalk --pid $pid_file --iterations 1 -- --defaults-file=$cnf --socket=/tmp/12346/mysql_sandbox12346.sock >$log_file 2>&1");
my $output = `cat $dest/nostalk-slave-status|grep Slave_IO_Running`;

like(
   $output,
   qr/Slave_IO_Running: Yes/,
   "SHOW SLAVE STATUS outputs gathered."
);

is(
   $retval >> 8,
   0,
   "Exit 0"
);

# #############################################################################
# Done.
# #############################################################################


cleanup();
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
