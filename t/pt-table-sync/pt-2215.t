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
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
elsif ( $sandbox_version lt '8.0' and $ENV{FORK} ne 'mariadb' ) {
   plan skip_all => "Requires MySQL 8.0 or newer or MariaDB";
}
else {
   plan tests => 3;
}

my ($output, $exit_code);
my @args = (qw(--sync-to-source -t sakila.actor --print --chunk-size 100));

my $to = 'TO';
$ENV{FORK} eq 'mariadb' and $to = 'FOR';

$sb->do_as_root(
   'source',
   q/CREATE USER `vinnie`@`%` IDENTIFIED BY 'percona123'/,
   q/GRANT USAGE ON *.* TO `vinnie`@`%`/,
   q/CREATE ROLE `dba`/,
   q/GRANT ALL PRIVILEGES ON *.* TO `dba` WITH GRANT OPTION/,
   q/GRANT `dba` TO `vinnie`@`%`/,
   qq/SET DEFAULT ROLE `dba` ${to} `vinnie`@`%`/,
);

if ( $ENV{FORK} ne 'mariadb') {
   diag(`/tmp/12345/use -h127.1 -P12345 -uvinnie -ppercona123 --ssl-mode=DISABLED --get-server-public-key -e 'select 1' 2>&1 > /dev/null`);
   diag(`/tmp/12345/use -h127.1 -P12346 -uvinnie -ppercona123 --ssl-mode=DISABLED --get-server-public-key -e 'select 1' 2>&1 > /dev/null`);
   diag(`/tmp/12345/use -h127.1 -P12347 -uvinnie -ppercona123 --ssl-mode=DISABLED --get-server-public-key -e 'select 1' 2>&1 > /dev/null`);
}

$sb->load_file('source', "t/pt-online-schema-change/samples/ssl_dsns.sql");

($output, $exit_code) = full_output(
   sub { pt_table_sync::main('h=127.1,P=12346,D=sakila,t=actor,u=vinnie,p=percona123', @args) },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for the user with privileges granted by the role"
) or diag($output);

unlike(
   $output,
   qr/You do not have the PROCESS privilege at/,
   'No error for missing PROCESS privilege'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root(
   'source',
   q/DROP USER `vinnie`@`%`/,
   q/DROP ROLE `dba`/,
);

$sb->wipe_clean($source_dbh);
$sb->wait_for_replicas();
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
