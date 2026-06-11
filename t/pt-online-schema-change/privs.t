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

#if ( !$ENV{SLOW_TESTS} ) {
#   plan skip_all => "pt-online-schema-change/privs.t is a top 5 slowest file; set SLOW_TESTS=1 to enable it.";
#}

use Data::Dumper;
use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}
elsif ( !@{$source_dbh->selectall_arrayref("show databases like 'sakila'")} ) {
   plan skip_all => 'sakila database is not loaded';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my $source_dsn = 'h=127.1,P=12345,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $row;
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# ############################################################################
# --recursion-method=none to avoid SHOW REPLICAS
# https://bugs.launchpad.net/percona-toolkit/+bug/987694
# ############################################################################
diag(`/tmp/12345/use -u root < $trunk/$sample/osc-user.sql`);
PerconaTest::wait_for_table($replica1_dbh, "mysql.tables_priv", "user='osc_user'");

$sb->load_file('source', "$sample/basic_no_fks_innodb.sql");

($output, $exit_status) = full_output(
   sub { $exit_status = pt_online_schema_change::main(@args,
      "$source_dsn,u=osc_user,D=pt_osc,t=t,s=1", '--alter', 'drop column id',
      qw(--execute),
      # Comment out this line and the tests fail because osc_user
      # doesn't have privs to SHOW REPLICAS.  This proves that
      # --recursion-method none is working.
      qw(--recursion-method none)
   ) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Limited user (bug 987694): 0 exit"
 ) or diag($exit_status);

like(
   $output,
   qr/Successfully altered `pt_osc`.`t`/,
   "Limited user (bug 987694): altered table"
) or diag($output);

diag(`/tmp/12345/use -u root -e "drop user 'osc_user'\@'%'"`);
wait_until(
   sub {
      my $rows=$replica2_dbh->selectall_arrayref("SELECT user FROM mysql.user");
      return !grep { ($_->[0] || '') ne 'osc_user' } @$rows;
   }
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
