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
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my $master_dsn = 'h=127.1,P=12348,u=msandbox,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# ############################################################################
# pt-online-schema-change doesn't work with ANSI_QUOTES + some other sql_modes
# https://bugs.launchpad.net/percona-toolkit/+bug/1058285
# ############################################################################
$sb->load_file('master1', "$sample/sql-mode-bug-1058285.sql");

my ($orig_sql_mode) = $dbh->selectrow_array(q{SELECT @@SQL_MODE});
# check that ANSI_QUOTES and ANSI is there
ok(
   $orig_sql_mode =~ /ANSI_QUOTES.*ANSI/,
   "ANSI modes set"
);

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
) or diag($output);

unlike(
   $output,
   qr/errno: 121/,
   "No error 121 (bug 1058285)"
);

my ($sql_mode) = $dbh->selectrow_array(q{SELECT @@SQL_MODE});
is(
   $sql_mode,
   $orig_sql_mode,
   "--dry-run SQL_MODE not changed"
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

($sql_mode) = $dbh->selectrow_array(q{SELECT @@SQL_MODE});
is(
   $sql_mode,
   $orig_sql_mode,
   "--execute SQL_MODE not changed"
);

# ############################################################################
# pt-online-schema-change foreign key error
# Customer issue 26211
# ############################################################################
$sb->load_file('master1', "$sample/issue-26211.sql");

my $retval;
($output, $retval) = full_output(sub { pt_online_schema_change::main(@args,
                              '--alter-foreign-keys-method', 'auto',
                              '--no-check-replication-filters',
                              '--alter', "ENGINE=InnoDB",
                              '--execute', "$master_dsn,D=bug_26211,t=prm_inst")});

is(
   $retval,
   0,
   "Issue 26211: Lives ok"
) or diag($output);

unlike(
   $output,
   qr/\QI need a max_rows argument/,
   "Issue 26211: No error message"
);

$dbh->do(q{DROP DATABASE IF EXISTS `bug_26211`});

# #############################################################################
# Done.
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
