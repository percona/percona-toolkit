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
my $dbh1 = $sb->get_dbh_for('master');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 10;
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-deadlock-logger -F $cnf h=127.1";

$sb->wipe_clean($dbh1);
$sb->create_dbs($dbh1, ['test']);

# #############################################################################
# Issue 248: Add --user, --pass, --host, etc to all tools
# #############################################################################

# Test that source DSN inherits from --user, etc.
$output = `$trunk/bin/pt-deadlock-logger h=127.1,D=test,u=msandbox,p=msandbox --clear-deadlocks test.make_deadlock --port 12345 2>&1`;
unlike(
   $output,
   qr/failed/,
   'Source DSN inherits from standard connection options (issue 248)'
);

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch /tmp/mk-script.pid`;
$output = `$cmd --clear-deadlocks test.make_deadlock --port 12345 --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid already exists},
   'Dies if PID file already exists (--pid without --daemonize) (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;

# #############################################################################
# Check daemonization
# #############################################################################
my $deadlocks_tbl = load_file('t/pt-deadlock-logger/deadlocks_tbl.sql');
$dbh1->do('USE test');
$dbh1->do('DROP TABLE IF EXISTS deadlocks');
$dbh1->do("$deadlocks_tbl");

my $pid_file = '/tmp/mk-deadlock-logger.pid';
unlink $pid_file
   and diag("Unlinked existing $pid_file");

`$cmd --dest D=test,t=deadlocks --daemonize --run-time 6s --interval 1s --pid $pid_file 1>/dev/null 2>/dev/null`;
$output = `ps -eaf | grep '$cmd \-\-dest '`;
like($output, qr/\Q$cmd/, 'It lives daemonized');

PerconaTest::wait_for_files($pid_file);
ok(-f $pid_file, 'PID file created');
my ($pid) = $output =~ /\s+(\d+)\s+/;
chomp($output = slurp_file($pid_file));
is($output, $pid, 'PID file has correct PID');

# Kill it
PerconaTest::wait_until(sub { !kill 0, $pid });
ok(! -f $pid_file, 'PID file removed');

# Check that it won't run if the PID file already exists (issue 383).
diag(`touch $pid_file`);
ok(
   -f $pid_file,
   'PID file already exists'
);

$output = `$cmd --dest D=test,t=deadlocks --daemonize --run-time 1s --interval 1s --pid $pid_file 2>&1`;
like(
   $output,
   qr/PID file .+ already exists/,
   'Does not run if PID file already exists'
);

$output = `ps -eaf | grep 'pt-deadlock-logger \-\-dest '`;
unlike(
   $output,
   qr/$cmd/,
   'It does not lived daemonized'
);

unlink $pid_file;

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
