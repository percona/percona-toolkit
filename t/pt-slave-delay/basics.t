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
my $slave1_dbh  = $sb->get_dbh_for('slave1');
my $slave2_dbh  = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}
else {
   plan tests => 6;
}

my $output;
my $cnf = '/tmp/12346/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-slave-delay -F $cnf h=127.1";

$output = `$cmd --help`;
like($output, qr/Prompt for a password/, 'It compiles');

# #############################################################################
# Issue 149: h is required even with S, for slavehost argument
# #############################################################################
$output = `$trunk/bin/pt-slave-delay --run-time 1s --delay 1s --interval 1s S=/tmp/12346/mysql_sandbox12346.sock 2>&1`;
unlike($output, qr/Missing DSN part 'h'/, 'Does not require h DSN part');

# #############################################################################
# Issue 215.  Specify SLAVE-HOST and MASTER-HOST, but MASTER-HOST does not have
# binary logging turned on, so SHOW MASTER STATUS is empty.  (This happens quite
# easily when you connect to a SLAVE-HOST twice by accident.)  To reproduce,
# just disable log-bin and log-slave-updates on the slave.
# #####1#######################################################################
diag(`cp /tmp/12346/my.sandbox.cnf /tmp/12346/my.sandbox.cnf-original`);
diag(`sed -i.bak -e '/log-bin/d' -e '/log_slave_updates/d' /tmp/12346/my.sandbox.cnf`);
diag(`/tmp/12346/stop >/dev/null`);
diag(`/tmp/12346/start >/dev/null`);

$output = `$trunk/bin/pt-slave-delay --delay 1s h=127.1,P=12346,u=msandbox,p=msandbox h=127.1 2>&1`;
like(
   $output,
   qr/Binary logging is disabled/,
   'Detects master that is not a master'
);

diag(`/tmp/12346/stop >/dev/null`);
diag(`mv /tmp/12346/my.sandbox.cnf-original /tmp/12346/my.sandbox.cnf`);
diag(`/tmp/12346/start >/dev/null`);
diag(`/tmp/12346/use -e "set global read_only=1"`);

$slave2_dbh->do('STOP SLAVE');
$slave2_dbh->do('START SLAVE');

# #############################################################################
# Check --use-master
# #############################################################################
$output = `$trunk/bin/pt-slave-delay --run-time 1s --interval 1s --use-master --host 127.1 --port 12346 -u msandbox -p msandbox`;
sleep 1;
like(
   $output,
   qr/slave running /,
   '--use-master'
);

$output = `$trunk/bin/pt-slave-delay --run-time 1s --interval 1s --use-master --host 127.1 --port 12345 -u msandbox -p msandbox 2>&1`;
like(
   $output,
   qr/No SLAVE STATUS found/,
   'No SLAVE STATUS on master'
);

# Sometimes the slave will be in a state of "reconnecting to master" that will
# take a while. Help that along. But, we've disconnected $slave1_dbh by doing
# 'stop' on the sandbox above, so we need to reconnect.
$slave2_dbh->do('STOP SLAVE');
$slave2_dbh->do('START SLAVE');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
