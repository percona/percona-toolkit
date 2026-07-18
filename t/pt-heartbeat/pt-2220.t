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
require "$trunk/bin/pt-heartbeat";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

$sb->create_dbs($dbh, ['test']);

my ($output, $exit_code);
my $cnf       = '/tmp/12345/my.sandbox.cnf';
my $cmd       = "$trunk/bin/pt-heartbeat -F $cnf ";

$dbh->do('drop table if exists test.heartbeat');
$dbh->do(q{CREATE TABLE test.heartbeat (
             id int NOT NULL PRIMARY KEY,
             ts datetime NOT NULL
          ) ENGINE=MEMORY});
$sb->wait_for_replicas;

$sb->do_as_root('source', 'SET GLOBAL read_only=0, super_read_only=0');

($output, $exit_code) = full_output(
   sub { pt_heartbeat::main("F=$cnf,h=127.1,P=12345",
      qw(-D test --check-read-only --update --utc --run-time=5)
   ) },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "pt-heartbeat exited with 0 with read_only=0, super_read_only=0"
) or diag($exit_code);

is(
   $output,
   '',
   "Nothing printed with read_only=0, super_read_only=0"
) or diag($output);

$sb->do_as_root('source', 'SET GLOBAL read_only=1, super_read_only=0');

($output, $exit_code) = full_output(
   sub { pt_heartbeat::main("F=$cnf,h=127.1,P=12345",
      qw(-D test --check-read-only --update --utc --run-time=5)
   ) },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "pt-heartbeat exited with 0 with read_only=1, super_read_only=0"
) or diag($exit_code);

is(
   $output,
   '',
   "Nothing printed with read_only=1, super_read_only=0"
) or diag($output);

$sb->do_as_root('source', 'SET GLOBAL super_read_only=1');

($output, $exit_code) = full_output(
   sub { pt_heartbeat::main("F=$cnf,h=127.1,P=12345",
      qw(-D test --check-read-only --update --utc --run-time=5)
   ) },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "pt-heartbeat exited with 0 with read_only=1, super_read_only=1"
) or diag($exit_code);

is(
   $output,
   '',
   "Nothing printed with read_only=1, super_read_only=1"
) or diag($output);

unlike(
   $output,
   qr/The MySQL server is running with the --super-read-only option so it cannot execute this statement/,
   "No error printed with read_only=1, super_read_only=1"
) or diag($output);

$sb->do_as_root('source', 'SET GLOBAL read_only=0, super_read_only=0');

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('source', 'SET GLOBAL read_only=0, super_read_only=0');

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");

done_testing;
exit;
