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
# that such-and-such happened on specific replica hosts, but
# the sandbox servers are all on one host so all replicas have
# the same hostname.
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use Data::Dumper;
use PerconaTest;
use Sandbox;

# Fix @INC because pt-table-checksum uses subclass OobNibbleIterator.
require "$trunk/bin/pt-table-checksum";

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
elsif ( !@{$source_dbh->selectall_arrayref("show databases like 'sakila'")} ) {
   plan skip_all => 'sakila database is not loaded';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
my $source_dsn = 'h=127.1,P=12345,s=1';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $row;
my $output;
my $exit_status;
my $sample  = "t/pt-table-checksum/samples/";

# ############################################################################
# Should always create schema and tables with IF NOT EXISTS
# https://bugs.launchpad.net/percona-toolkit/+bug/950294
# ############################################################################

$source_dbh->do("DROP DATABASE IF EXISTS percona");
diag(`/tmp/12345/use -u root < $trunk/t/lib/samples/ro-checksum-user.sql 2>/dev/null`);
PerconaTest::wait_for_table($replica2_dbh, "mysql.user", "user='ro_checksum_user'");

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args,
      "$source_dsn,u=ro_checksum_user,p=msandbox",
      qw(--recursion-method none)
   ) },
   stderr => 1,
);

like(
   $output,
   qr/\Qdatabase percona does not exist and it cannot be created automatically/,
   "Error if percona db doesn't exist and user can't create it",
);

$output = output(
   sub { pt_table_checksum::main(@args,
      "$source_dsn,u=ro_checksum_user,p=msandbox",
      qw(--recursion-method none --no-create-replicate-table)
   ) },
   stderr => 1,
);

like(
   $output,
   qr/\Qdatabase percona does not exist and --no-create-replicate-table was/,
   "Error if percona db doesn't exist and --no-create-replicate-table",
);

diag(`/tmp/12345/use -u root -e "drop user 'ro_checksum_user'\@'%'"`);
wait_until(
   sub {
      my $rows=$replica2_dbh->selectall_arrayref("SELECT user FROM mysql.user");
      return !grep { ($_->[0] || '') eq 'ro_checksum_user' } @$rows;
   }
);

# ############################################################################
# --recursion-method=none to avoid SHOW REPLICA HOSTS
# https://bugs.launchpad.net/percona-toolkit/+bug/987694
# ############################################################################

# Create percona.checksums because ro_checksum_user doesn't have the privs.
pt_table_checksum::main(@args,
   "$source_dsn,u=msandbox,p=msandbox",
   qw(-t sakila.country --quiet --quiet));

diag(`/tmp/12345/use -u root < $trunk/t/lib/samples/ro-checksum-user.sql 2>/dev/null`);
PerconaTest::wait_for_table($replica1_dbh, "mysql.tables_priv", "user='ro_checksum_user'");

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args,
      "$source_dsn,u=ro_checksum_user,p=msandbox",
      # Comment out this line and the tests fail because ro_checksum_user
      # doesn't have privs to SHOW REPLICA HOSTS.  This proves that
      # --recursion-method none is working.
      qw(--recursion-method none --no-create-replicate-table)
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

($output, $exit_status) = full_output(
   sub { pt_table_checksum::main(@args,
      "$source_dsn,u=ro_checksum_user,p=msandbox",
      qw(--recursion-method none)
   ) }
);

is(
   $exit_status,
   0,
   "No error if db exists on the source, can't CREATE DATABASE, --no-create-replicate-table was not specified, but the database does exist in all replicas"
);

diag(qx{/tmp/12345/use -u root -e 'DROP TABLE `percona`.`checksums`'});

($output, $exit_status) = full_output(
   sub { pt_table_checksum::main(@args,
      "$source_dsn,u=ro_checksum_user,p=msandbox",
      qw(--recursion-method none --no-create-replicate-table)
   ) },
);

like($output,
   qr/\Q--replicate table `percona`.`checksums` does not exist and --no/,
   "Error if checksums db doesn't exist and --no-create-replicate-table"
);

diag(`/tmp/12345/use -u root -e "drop user 'ro_checksum_user'\@'%'"`);
wait_until(
   sub {
      my $rows=$replica2_dbh->selectall_arrayref("SELECT user FROM mysql.user");
      return !grep { ($_->[0] || '') eq 'ro_checksum_user' } @$rows;
   }
);

# #############################################################################
# Bug 916168: bug in pt-table-checksum privileges check
# #############################################################################
diag(`/tmp/12345/use -u root < $trunk/t/pt-table-checksum/samples/privs-bug-916168.sql`);

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args,
      "$source_dsn,u=test_user,p=foo", qw(-t sakila.country)) },
);

is(
   $exit_status,
   0,
   "test_user privs work (bug 916168) returned no error"
) or diag($exit_status);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   109,
   "test_user privs work (bug 916168)"
);

unlike(
   $output,
   qr/The current checksum table uses deprecated column names./,
   'Deprecation warning not printed'
);

diag(`/tmp/12345/use -u root -e "drop user 'test_user'\@'%'"`);
wait_until(
   sub {
      my $rows=$replica2_dbh->selectall_arrayref("SELECT user FROM mysql.user");
      return !grep { ($_->[0] || '') eq 'test_user' } @$rows;
   }
);

# #############################################################################
# Legacy checksum table
# #############################################################################
diag(`/tmp/12345/use -u root < $trunk/t/pt-table-checksum/samples/privs-bug-916168-legacy.sql`);

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args,
      "$source_dsn,u=test_user,p=foo", qw(-t sakila.country)) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "test_user privs work (bug 916168) returned no error"
) or diag($exit_status);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   109,
   "test_user privs work (bug 916168)"
);

like(
   $output,
   qr/The current checksum table uses deprecated column names./,
   'Deprecation warning printed for legacy table'
);

diag(`/tmp/12345/use -u root -e "drop user 'test_user'\@'%'"`);
wait_until(
   sub {
      my $rows=$replica2_dbh->selectall_arrayref("SELECT user FROM mysql.user");
      return !grep { ($_->[0] || '') eq 'test_user' } @$rows;
   }
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
