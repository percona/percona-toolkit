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
my $source_dbh = $sb->get_dbh_for('source');
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';

my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica1_dsn = 'h=127.1,P=12346,u=unprivileged,p=password,s=1';

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

sub start_thread {
    my ($dsn_opts, $sleep) = @_;

    my $dp = new DSNParser(opts=>$dsn_opts);
    my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
    my $dbh= $sb->get_dbh_for('replica1');
    my $rows = $dbh->selectall_arrayref('SHOW PROCESSLIST', { Slice => {} });
    for my $row (@$rows) {
        if ($row->{user} eq 'unprivileged') {
            $dbh->do("kill $row->{id}");
        }
    }
}

my $create_table_sql = <<__EOQ;
  CREATE TABLE IF NOT EXISTS sakila.heartbeat (
    ts                    varchar(26) NOT NULL,
    server_id             int unsigned NOT NULL PRIMARY KEY,
    file                  varchar(255) DEFAULT NULL,    -- SHOW BINARY LOG STATUS
    position              bigint unsigned DEFAULT NULL, -- SHOW BINARY LOG STATUS
    relay_${source_name}_log_file varchar(255) DEFAULT NULL,    -- SHOW REPLICA STATUS
    exec_${source_name}_log_pos   bigint unsigned DEFAULT NULL  -- SHOW REPLICA STATUS
  );
__EOQ

$sb->do_as_root('source', "$create_table_sql");
if ($sandbox_version eq '8.0') {
    $sb->do_as_root('replica1', 'CREATE USER "unprivileged"@"localhost" IDENTIFIED WITH mysql_native_password BY "password"');
} else {
    $sb->do_as_root('replica1', 'CREATE USER "unprivileged"@"localhost" IDENTIFIED BY "password"');
}
$sb->do_as_root('replica1', 'GRANT SELECT, INSERT, UPDATE, REPLICATION CLIENT ON *.* TO "unprivileged"@"localhost"');
$sb->do_as_root('replica1', "FLUSH TABLES WITH READ LOCK;");
$sb->do_as_root('replica1', "SET GLOBAL read_only = 1;");

my $thread = threads->create('start_thread', $dsn_opts, 4);
$thread->detach();
threads->yield();

my $output = `PTDEBUG=1 $trunk/bin/pt-heartbeat --database=sakila --table heartbeat --read-only-interval 2 --check-read-only --run-time 5 --update $replica1_dsn 2>&1`;

unlike (
    $output,
    qr/Lost connection to MySQL/,
    'PT-1508 --read-only-interval',
);

$source_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('source', 'DROP TABLE IF EXISTS sakila.heartbeat');
$sb->do_as_root('replica1', 'DROP USER "unprivileged"@"localhost"');

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
