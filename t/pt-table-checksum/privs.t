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

# Hostnames make testing less accurate.  Tests need to see
# that such-and-such happened on specific slave hosts, but
# the sandbox servers are all on one host so all slaves have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use Data::Dumper;
use PerconaTest;
use Sandbox;

# Fix @INC because pt-table-checksum uses subclass OobNibbleIterator.
shift @INC;  # our unshift (above)
shift @INC;  # PerconaTest's unshift
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave2_dbh = $sb->get_dbh_for('slave2');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !@{$master_dbh->selectall_arrayref("show databases like 'sakila'")} ) {
   plan skip_all => 'sakila database is not loaded';
}
else {
   plan tests => 3;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --lock-wait-timeout=3 else the tool will die.
my $master_dsn = 'h=127.1,P=12345';
my @args       = (qw(--lock-wait-timeout 3));
my $row;
my $output;
my $exit_status;
my $sample  = "t/pt-table-checksum/samples/";

# ############################################################################
# --recursion-method=none to avoid SHOW SLAVE HOSTS
# https://bugs.launchpad.net/percona-toolkit/+bug/987694
# ############################################################################

# Create percona.checksums because ro_checksum_user doesn't have the privs.
pt_table_checksum::main(@args,
   "$master_dsn,u=msandbox,p=msandbox",
   qw(-t sakila.country --quiet --quiet));

diag(`/tmp/12345/use -u root < $trunk/t/lib/samples/ro-checksum-user.sql`);
PerconaTest::wait_for_table($slave1_dbh, "mysql.tables_priv", "user='ro_checksum_user'");

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args,
      "$master_dsn,u=ro_checksum_user,p=msandbox",
      # Comment out this line and the tests fail because ro_checksum_user
      # doesn't have privs to SHOW SLAVE HOSTS.  This proves that
      # --recursion-method none is working.
      qw(--recursion-method none)
   ) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Read-only user (bug 987694): 0 exit"
);

like(
   $output,
   qr/ sakila.store$/m,
   "Read-only user (bug 987694): checksummed rows"
);

diag(`/tmp/12345/use -u root -e "drop user 'ro_checksum_user'\@'%'"`);
wait_until(
   sub {
      my $rows=$slave2_dbh->selectall_arrayref("SELECT user FROM mysql.user");
      return !grep { ($_->[0] || '') ne 'ro_checksum_user' } @$rows;
   }
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
