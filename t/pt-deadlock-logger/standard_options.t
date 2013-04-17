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
require "$trunk/bin/pt-deadlock-logger";

my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $output;
my $dsn  = $sb->dsn_for('master');
my @args = ($dsn, qw(--iterations 1));

$sb->wipe_clean($dbh);
$sb->create_dbs($dbh, ['test']);

# #############################################################################
# Issue 248: Add --user, --pass, --host, etc to all tools
# #############################################################################

# Test that source DSN inherits from --user, etc.
$output = output(
   sub {
      pt_deadlock_logger::main(
         "h=127.1,D=test,u=msandbox,p=msandbox",
         qw(--clear-deadlocks test.make_deadlock --port 12345),
         qw(--iterations 1)
      )
   }
);

unlike(
   $output,
   qr/failed/,
   'Source DSN inherits from standard connection options (issue 248)'
);

# #############################################################################
# Issue 391: Add --pid option to all scripts
# #############################################################################

my $pid_file = "/tmp/pt-deadlock-logger-test.pid.$PID";
diag(`touch $pid_file`);

$output = output(
   sub {
      pt_deadlock_logger::main(@args, '--pid', $pid_file)
   },
   stderr => 1,
);

like(
   $output,
   qr{PID file $pid_file already exists},
   'Dies if PID file already exists (--pid without --daemonize) (issue 391)'
);

unlink $pid_file if -f $pid_file;

# #############################################################################
# Check daemonization
# #############################################################################
$dbh->do('USE test');
$dbh->do('DROP TABLE IF EXISTS deadlocks');
$sb->load_file('master', 't/pt-deadlock-logger/samples/deadlocks_tbl.sql', 'test');

$output = `$trunk/bin/pt-deadlock-logger $dsn --dest D=test,t=deadlocks --daemonize --run-time 10 --interval 1 --pid $pid_file 1>/dev/null 2>/dev/null`;

PerconaTest::wait_for_files($pid_file);

$output = `ps x | grep 'pt-deadlock-logger $dsn' | grep -v grep`;
like(
   $output,
   qr/\Qpt-deadlock-logger $dsn/,
   'It lives daemonized'
) or diag($output);

my ($pid) = $output =~ /(\d+)/;

ok(
   -f $pid_file,
   'PID file created'
) or diag($output);

chomp($output = slurp_file($pid_file));
is(
   $output,
   $pid,
   'PID file has correct PID'
);

# Kill it
kill 2, $pid;
PerconaTest::wait_until(sub { !kill 0, $pid });
ok(! -f $pid_file, 'PID file removed');

# Check that it won't run if the PID file already exists (issue 383).
diag(`touch $pid_file`);
ok(
   -f $pid_file,
   'PID file already exists'
);

$output = output(
   sub {
      pt_deadlock_logger::main(@args, '--pid', $pid_file,
         qw(--daemonize))
   },
   stderr => 1,
);

like(
   $output,
   qr/PID file $pid_file already exists/,
   'Does not run if PID file already exists'
);

$output = `ps x | grep 'pt-deadlock-logger $dsn' | grep -v grep`;

is(
   $output,
   "",
   'It does not lived daemonized'
);

unlink $pid_file;

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
