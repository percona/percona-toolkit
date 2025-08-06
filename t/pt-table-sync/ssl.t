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
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}
else {
   plan tests => 13;
}

my ($output, $exit_code);
my @args = (qw(--sync-to-source -t sakila.actor -v -v --print --chunk-size 100));

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT ALL ON sakila.* TO sha256_user@'%'/,
   q/GRANT ALL ON percona.* TO sha256_user@'%'/,
   q/GRANT SELECT ON test_ssl.* TO sha256_user@'%'/,
   q/GRANT REPLICATION CLIENT ON *.* TO sha256_user@'%'/,
   q/GRANT PROCESS ON *.* TO sha256_user@'%'/,
);

$sb->load_file('source', "t/pt-online-schema-change/samples/ssl_dsns.sql");

($output, $exit_code) = full_output(
   sub { pt_table_sync::main('h=127.1,P=12346,D=sakila,t=film,u=sha256_user,p=sha256_user%password,s=0', @args) },
   stderr => 1,
);

isnt(
   $exit_code,
   0,
   "Error raised when SSL connection is not used"
) or diag($output);

like(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'Secure connection error raised when no SSL connection used'
) or diag($output);

($output, $exit_code) = full_output(
   sub { pt_table_sync::main('h=127.1,P=12346,D=sakila,t=film,u=sha256_user,p=sha256_user%password,s=1', @args) },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error'
) or diag($output);

like(
   $output,
   qr/WHERE \(`film_id` = 0\)/,
   "Zero chunk"
);

($output, $exit_code) = full_output(
   sub { pt_table_sync::main('D=sakila,t=film',
         qw(--host 127.1 --port 12346 --user sha256_user),
         qw(--password sha256_user%password --mysql_ssl 1), @args) },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password with option --mysql_ssl"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with option --mysql_ssl'
) or diag($output);

like(
   $output,
   qr/WHERE \(`film_id` = 0\)/,
   "Zero chunk with option --mysql_ssl"
);

# Prepare checksums table
diag(`$trunk/bin/pt-table-checksum F=t/pt-archiver/samples/pt-191.cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1 -d sakila --recursion-method=dsn=F=t/pt-archiver/samples/pt-191.cnf,D=test_ssl,t=dsns,h=127.0.0.1,P=12345,u=sha256_user,p=sha256_user%password,s=1 2>&1 >/dev/null`);

@args = (qw(--recursion-method=dsn --replicate=percona.checksums -t sakila.actor -v -v --print --chunk-size 100));
($output, $exit_code) = full_output(
   sub {
      pt_table_sync::main(
         'F=t/pt-archiver/samples/pt-191,h=127.1,P=12346,D=sakila,t=film,u=sha256_user,p=sha256_user%password,s=1',
         @args,
         "--recursion-method=dsn=F=t/pt-archiver/samples/pt-191-replica1.cnf,D=test_ssl,t=dsns,h=127.0.0.1,P=12345,u=sha256_user,p=sha256_user%password,s=1"
      ) },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for SSL options in the configuration file"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with correct SSL options in the configuration file'
) or diag($output);

($output, $exit_code) = full_output(
   sub {
      pt_table_sync::main(
         'F=t/pt-archiver/samples/pt-191-error.cnf,h=127.1,P=12345,D=sakila,t=film,u=sha256_user,p=sha256_user%password,s=1',
         @args,
         "--recursion-method=dsn=F=t/pt-archiver/samples/pt-191.cnf,D=test_ssl,t=dsns,h=127.0.0.1,P=12345,u=sha256_user,p=sha256_user%password,s=1"
      ) },
   stderr => 1,
);

isnt(
   $exit_code,
   0,
   "Error for invalid SSL options in the configuration file"
) or diag($output);

like(
   $output,
   qr/SSL connection error: Unable to get private key at/,
   'SSL connection error with incorrect SSL options in the configuration file'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('source', q/DROP USER 'sha256_user'@'%'/);

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
