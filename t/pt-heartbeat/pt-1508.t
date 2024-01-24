#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads ('yield');

use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempfile /;

plan tests => 2;

require "$trunk/bin/pt-heartbeat";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';

my ($tfh, $pid_file) = tempfile();
close($tfh);
unlink($pid_file);

my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave1_dsn = 'h=127.1,P=12346,u=unprivileged,p=password';

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

sub start_thread {
    my ($dsn_opts, $sleep, $pid_file) = @_;

    my $dp = new DSNParser(opts=>$dsn_opts);
    my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
    my $dbh= $sb->get_dbh_for('slave1');
    diag("Thread started");

    warn "Sleeping $sleep seconds";
    sleep($sleep);
    $dbh->do("UNLOCK TABLES");
    $dbh->do("SET GLOBAL read_only = 0;");
}

my $create_table_sql = <<__EOQ;
  CREATE TABLE IF NOT EXISTS sakila.heartbeat (
    ts                    varchar(26) NOT NULL,
    server_id             int unsigned NOT NULL PRIMARY KEY,
    file                  varchar(255) DEFAULT NULL,    -- SHOW MASTER STATUS
    position              bigint unsigned DEFAULT NULL, -- SHOW MASTER STATUS
    relay_master_log_file varchar(255) DEFAULT NULL,    -- SHOW SLAVE STATUS
    exec_master_log_pos   bigint unsigned DEFAULT NULL  -- SHOW SLAVE STATUS
  );
__EOQ

$sb->do_as_root('master', "$create_table_sql");
if ($sandbox_version ge '8.0') {
    $sb->do_as_root('slave1', 'CREATE USER "unprivileged"@"localhost" IDENTIFIED WITH mysql_native_password BY "password"');
} else {
    $sb->do_as_root('slave1', 'CREATE USER "unprivileged"@"localhost" IDENTIFIED BY "password"');
}
$sb->do_as_root('slave1', 'GRANT SELECT, INSERT, UPDATE, REPLICATION CLIENT ON *.* TO "unprivileged"@"localhost"');
$sb->do_as_root('slave1', "FLUSH TABLES WITH READ LOCK;");
$sb->do_as_root('slave1', "SET GLOBAL read_only = 1;");

my $thread = threads->create('start_thread', $dsn_opts, 4, $pid_file);
$thread->detach();
threads->yield();

my $output = `PTDEBUG=1 $trunk/bin/pt-heartbeat --database=sakila --table heartbeat --read-only-interval 2 --check-read-only --run-time 5 --update $slave1_dsn 2>&1`;

like (
    $output,
    qr/Sleeping for 2 seconds/,
    'PT-1508 --read-only-interval',
);

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('master', 'DROP TABLE IF EXISTS sakila.heartbeat');
$sb->do_as_root('slave1', 'DROP USER "unprivileged"@"localhost"');

$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
