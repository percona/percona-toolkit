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

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
else {
   plan tests => 4;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my @args     = (qw(--lock-wait-timeout 3 --explain --tables sakila.country)); 
my $cnf      = "/tmp/12345/my.sandbox.cnf";
my $pid_file = "/tmp/mk-table-checksum-test.pid";
my $output;

# ############################################################################
# DSN should inherit connection options (--port, etc.)
# ############################################################################

$output = output(
   sub { pt_table_checksum::main(@args, 'h=127.1',
      qw(--port 12345 --user msandbox --password msandbox)) },
);
like(
   $output,
   qr/-- sakila\.country/,
   'DSN inherits values from --port, etc. (issue 248)'
);

# Same test but this time intentionally use the wrong port so the connection
# fails so we know that the previous test didn't work because your system
# has a .my.cnf file or something.
eval {
   pt_table_checksum::main(@args, 'h=127.1',
      qw(--port 4 --user msandbox --password msandbox));
};
like(
   $EVAL_ERROR,
   qr/port=4.+failed/,
   'DSN truly inherits values from --port, etc. (issue 248)'
);

# #############################################################################
# Issue 947: mk-table-checksum crashes if h DSN part is not given
# #############################################################################

$output = output(
   sub { pt_table_checksum::main(@args, "F=$cnf") },
);
like(
   $output,
   qr/-- sakila\.country/,
   "Doesn't crash if no h DSN part (issue 947)"
);

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
diag(`rm -rf $pid_file >/dev/null 2>&1`);
diag(`touch $pid_file`);

eval {
   pt_table_checksum::main(@args, $cnf, '--pid', $pid_file);
};
like(
   $EVAL_ERROR,
   qr/PID file $pid_file already exists/,
   'Dies if PID file already exists (issue 391)'
);

diag(`rm -rf $pid_file >/dev/null 2>&1`);

# #############################################################################
# Done.
# #############################################################################
exit;
