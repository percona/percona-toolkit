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

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my @args     = (qw(--set-vars innodb_lock_wait_timeout=3 --explain --tables sakila.country),
                '--max-load', ''); 
my $cnf      = "/tmp/12345/my.sandbox.cnf";
my $pid_file = "/tmp/mk-table-checksum-test.pid";
my $output;
my $exit_status;

# ############################################################################
# Tool should connect to localhost without any options.
# ############################################################################

# This may not work because the sandbox servers aren't on localhost,
# but if your box has MySQL running on localhost then maybe it will,
# so we'll account for both of these possibilities.

eval {
   $exit_status = pt_table_checksum::main(@args);
};
if ( $EVAL_ERROR ) {
   # It's ok that this fails.  It means that your box, like mine, doesn't
   # have MySQL on localhost:3306:/tmp/mysql.socket/etc.
   like(
      $EVAL_ERROR,
      qr/connect\(';host=localhost;/,
      'Default DSN is h=localhost'
   );
}
else {
   # Apparently, your box is running MySQL on default ports.  That
   # means the tool ran, so it should run without errors.
   is(
      $exit_status,
      0,
      'Default DSN is h=localhost'
   );
}

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

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args, $cnf, '--pid', $pid_file) },
   stderr => 1,
);
like(
   $output,
   qr/PID file $pid_file exists/,
   'Dies if PID file already exists (issue 391)'
);

is(
   $exit_status,
   2,
   "Exit status 2 if if PID file already exist (bug 944051)"
);

diag(`rm -rf $pid_file >/dev/null 2>&1`);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
