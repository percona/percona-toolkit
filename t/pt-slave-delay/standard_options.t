#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More ;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-slave-delay";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to second sandbox master';
}
else {
   plan tests => 9;
}

my $output;
my $cmd = "$trunk/bin/pt-slave-delay -F /tmp/12346/my.sandbox.cnf h=127.1";

# Check daemonization
system("$cmd --delay 1m --interval 1s --run-time 5s --daemonize --pid /tmp/mk-slave-delay.pid");
$output = `ps -eaf | grep 'mk-slave-delay' | grep ' \-\-delay 1m '`;
like($output, qr/$cmd/, 'It lives daemonized');

ok(-f '/tmp/mk-slave-delay.pid', 'PID file created');
my ($pid) = $output =~ /\s+(\d+)\s+/;
$output = `cat /tmp/mk-slave-delay.pid`;
# If this test fails, it may be because another instances of
# mk-slave-delay is running.
is($output, $pid, 'PID file has correct PID');

# Kill it
diag(`kill $pid`);
wait_until(sub{!kill 0, $pid});
ok(! -f '/tmp/mk-slave-delay.pid', 'PID file removed');

# #############################################################################
# Check that SLAVE-HOST can be given by cmd line opts.
# #############################################################################
$output = `$trunk/bin/pt-slave-delay --run-time 1s --interval 1s --host 127.1 --port 12346 -u msandbox -p msandbox`;
sleep 1;
like(
   $output,
   qr/slave running /,
   'slave host given by cmd line opts'
);

# And check issue 248: that the slave host will inhert from --port, etc.
$output = `$trunk/bin/pt-slave-delay --run-time 1s --interval 1s 127.1 --port 12346 -u msandbox -p msandbox`;
sleep 1;
like(
   $output,
   qr/slave running /,
   'slave host inherits --port, etc. (issue 248)'
);

# #############################################################################
# Check --log.
# #############################################################################
`$cmd --run-time 1s --interval 1s --log /tmp/mk-slave-delay.log --daemonize`;
sleep 2;
$output = `cat /tmp/mk-slave-delay.log`;
`rm -f /tmp/mk-slave-delay.log`;
like(
   $output,
   qr/slave running /,
   '--log'
);

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch /tmp/mk-script.pid`;
$output = `$cmd --run-time 1s --interval 1s --use-master --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid already exists},
   'Dies if PID file already exists (--pid without --daemonize) (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
