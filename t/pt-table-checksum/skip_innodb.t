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
require "$trunk/bin/pt-table-checksum";

if ( $sandbox_version ge '5.6' ) {
   plan skip_all => 'Cannot disable InnoDB in MySQL 5.6';
}

diag("Stopping/reconfiguring/restarting sandboxes 12348 and 12349");
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
diag(`SKIP_INNODB=1 $trunk/sandbox/start-sandbox master 12348 >/dev/null`);

diag(`$trunk/sandbox/stop-sandbox 12349 >/dev/null`);
diag(`SKIP_INNODB=1 $trunk/sandbox/start-sandbox slave 12349 12348 >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master1');
my $slave_dbh  = $sb->get_dbh_for('master2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master 12348';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave 12349';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12348,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $output;
my $retval;

$output = output(
   sub { $retval = pt_table_checksum::main(@args) },
   stderr => 1,
);

like(
   $output,
   qr/mysql/,
   "Ran without InnoDB (bug 996110)"
);

is(
   $retval,
   0,
   "0 exit status (bug 996110)"
);

# #############################################################################
# Done.
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox 12349 12348 >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
