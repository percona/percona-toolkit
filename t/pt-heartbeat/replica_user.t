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
use SqlModes;
require "$trunk/bin/pt-heartbeat";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}

my $cnf  = "/tmp/12345/my.sandbox.cnf";
my ($output, $exit_code);
my $rows;

$source_dbh->do('CREATE DATABASE IF NOT EXISTS test');

# Create a new user that is going to be replicated on replicas.
if ($sandbox_version eq '8.0') {
    $sb->do_as_root("replica1", q/CREATE USER 'replica_user'@'localhost' IDENTIFIED WITH mysql_native_password BY 'replica_password'/);
} else {
    $sb->do_as_root("replica1", q/CREATE USER 'replica_user'@'localhost' IDENTIFIED BY 'replica_password'/);
}
$sb->do_as_root("replica1", q/GRANT REPLICATION CLIENT ON *.* TO 'replica_user'@'localhost'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);                

$sb->wait_for_replicas();

# Ensure we cannot connect to replicas using standard credentials
# Since replica2 is a replica of replica1, removing the user from the replica1 will remove
# the user also from replica2
$sb->do_as_root("replica1", q/RENAME USER 'msandbox'@'%' TO 'msandbox_old'@'%'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);
$sb->do_as_root("replica1", q/FLUSH TABLES/);

($output, $exit_code) = full_output(
   sub {
      pt_heartbeat::main(
         qw(-h 127.1 -u msandbox -p msandbox -P 12345 --database test),
         qw(--table heartbeat --create-table --update --interval 0.5  --run-time 2), 
         qw(--replica-user replica_user --replica-password replica_password)
      )
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "pt-heartbeat finished correctly"
) or diag($output);
 
$rows = `/tmp/12346/use -u root -s -e "select server_id from test.heartbeat"`;

chomp $rows;

is(
   $rows,
   12345,
   "Replica1 has source heartbeat",
);

unlike(
   $output,
   qr/Option --slave-user is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --replica-user provided'
) or diag($output);

unlike(
   $output,
   qr/Option --slave-password is deprecated and will be removed in future versions./,
   'Deprecation warning not printed when option --replica-password provided'
) or diag($output);

$source_dbh->do('TRUNCATE TABLE test.heartbeat');

$rows = `/tmp/12346/use -u root -s -e "select count(*) from test.heartbeat"`;

chomp $rows;

is(
   $rows,
   0,
   'Heartbeat table truncated on replica'
);

($output, $exit_code) = full_output(
   sub {
      pt_heartbeat::main(
         qw(-h 127.1 -u msandbox -p msandbox -P 12345 --database test),
         qw(--table heartbeat --create-table --update --interval 0.5  --run-time 2), 
         qw(--slave-user replica_user --slave-password replica_password)
      )
   },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "pt-heartbeat finished correctly"
) or diag($output);
 
$rows = `/tmp/12346/use -u root -s -e "select server_id from test.heartbeat"`;

chomp $rows;

is(
   $rows,
   12345,
   "Replica1 has source heartbeat",
);

like(
   $output,
   qr/Option --slave-user is deprecated and will be removed in future versions./,
   'Deprecation warning printed when option --slave-user provided'
) or diag($output);

like(
   $output,
   qr/Option --slave-password is deprecated and will be removed in future versions./,
   'Deprecation warning printed when option --slave-password provided'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
# Drop test user
$sb->do_as_root("replica1", q/DROP USER 'replica_user'@'localhost'/);
$sb->do_as_root("replica1", q/FLUSH PRIVILEGES/);

# Restore privilegs for the other test files
$sb->do_as_root("replica1", q/RENAME USER 'msandbox_old'@'%' TO 'msandbox'@'%'/);
$sb->do_as_root("source", q/FLUSH PRIVILEGES/);                
$sb->do_as_root("source", q/FLUSH TABLES/);

$sb->wipe_clean($source_dbh);

ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;
exit;
