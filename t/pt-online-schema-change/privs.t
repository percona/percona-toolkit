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
elsif ( !@{$master_dbh->selectall_arrayref('show databases like "sakila"')} ) {
   plan skip_all => 'sakila database is not loaded';
}
else {
   plan tests => 3;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345,p=msandbox';
my @args       = (qw(--lock-wait-timeout 3));
my $row;
my $output;
my $exit_status;
my $sample  = "t/pt-online-schema-change/samples/";

# ############################################################################
# --recursion-method=none to avoid SHOW SLAVE HOSTS
# https://bugs.launchpad.net/percona-toolkit/+bug/987694
# ############################################################################
diag(`/tmp/12345/use -u root < $trunk/$sample/osc-user.sql`);
PerconaTest::wait_for_table($slave_dbh, "mysql.tables_priv", "user='osc_user'");

$sb->load_file('master', "$sample/basic_no_fks.sql");
PerconaTest::wait_for_table($slave_dbh, "pt_osc.t", "id=20");

$output = output(
   sub { $exit_status = pt_online_schema_change::main(@args,
      "$master_dsn,u=osc_user,D=pt_osc,t=t", '--alter', 'drop column id',
      qw(--execute),
      # Comment out this line and the tests fail because osc_user
      # doesn't have privs to SHOW SLAVE HOSTS.  This proves that
      # --recursion-method none is working.
      qw(--recursion-method none)
   ) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Limited user (bug 987694): 0 exit"
);

like(
   $output,
   qr/Successfully altered `pt_osc`.`t`/,
   "Limited user (bug 987694): altered table"
);

diag(`/tmp/12345/use -u root -e "drop user 'osc_user'\@'%'"`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
