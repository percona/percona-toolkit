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

use Data::Dumper;
use PerconaTest;
use Sandbox;

require "$trunk/bin/pt-online-schema-change";

diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
diag(`MODE_ANSI=1 $trunk/sandbox/start-sandbox master 12348 >/dev/null`);

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master 12348';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12348,u=msandbox,p=msandbox';
my @args       = (qw(--lock-wait-timeout 3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# ############################################################################
# pt-online-schema-change doesn't work with ANSI_QUOTES + some other sql_modes
# https://bugs.launchpad.net/percona-toolkit/+bug/1058285
# ############################################################################
$sb->load_file('master1', "$sample/sql-mode-bug-1058285.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=issue26211,t=process_model_inst",
      "--alter", "ADD COLUMN foo int",
      qw(--dry-run --print --alter-foreign-keys-method auto)) },
);

is(
   $exit_status,
   0,
   "--dry-run exit 0 (bug 1058285)"
);

unlike(
   $output,
   qr/errno: 121/,
   "No error 121 (bug 1058285)"
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$master_dsn,D=issue26211,t=process_model_inst",
      "--alter", "ADD COLUMN foo int",
      qw(--execute --alter-foreign-keys-method auto)) },
);

is(
   $exit_status,
   0,
   "--execute exit 0 (bug 1058285)"
);

unlike(
   $output,
   qr/\QI need a max_rows argument/,
   "No 'I need a max_rows' error message (bug 1073996)"
);

# ANSI_QUOTES are on, so it's "foo" not `foo`.
my $rows = $dbh->selectrow_arrayref("SHOW CREATE TABLE issue26211.process_model_inst");
like(
   $rows->[1],
   qr/"foo"\s+int/i,
   "--alter actually worked (bug 1058285)"
);

# #############################################################################
# Done.
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
