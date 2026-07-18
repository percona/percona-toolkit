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
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my ($output, $exit_code);

# Testing if we are using DBD::mysql compiled with MariaDB library, which does not support enforcing SSL encryption
($output, $exit_code) = full_output(
   sub { pt_table_checksum::main(@args, 'h=127.1,P=12345,u=msandbox,p=msandbox,s=1', qw(-d test)) },
   stderr => 1,
);

if ( $exit_code == 0 || $output !~ /SSL connection error: Enforcing SSL encryption is not supported/ ) {
   plan skip_all => "Test requires DBD::mysql compiled with MariaDB library that does not support enforcing SSL encryption";
}
elsif ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}
else {
   plan tests => 15;
}

# #############################################################################
# Issue 388: mk-table-checksum crashes when column with comma in the name
# is used in a key
# #############################################################################

$sb->create_dbs($dbh, [qw(test)]);
$sb->load_file('source', 't/lib/samples/tables/issue-388.sql', 'test');

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT ALL ON test.* TO sha256_user@'%'/,
   q/GRANT SELECT ON test_ssl.* TO sha256_user@'%'/,
   q/GRANT ALL ON percona.* TO sha256_user@'%'/,
   q/GRANT REPLICATION SLAVE ON *.* TO sha256_user@'%'/,
   q/GRANT REPLICATION CLIENT ON *.* TO sha256_user@'%'/,
);

$sb->load_file('source', "t/pt-online-schema-change/samples/ssl_dsns.sql");
$dbh->do("insert into test.foo values (null, 'john, smith')");

($output, $exit_code) = full_output(
   sub { pt_table_checksum::main(@args, 'h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=0', qw(-d test)) },
   stderr => 1,
);

isnt(
   $exit_code,
   0,
   "Error raised when SSL connection is not used"
) or diag($output);

like(
   $output,
   qr/Access denied/,
   'Secure connection error raised when no SSL connection used'
) or diag($output);

($output, $exit_code) = full_output(
   sub { pt_table_checksum::main(@args, 'h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1', qw(-d test)) },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error'
) or diag($output);

unlike(
   $output,
   qr/Use of uninitialized value/,
   'No error (issue 388)'
);

like(
   $output,
   qr/^\S+\s+0\s+0\s+1\s+0\s+1\s+/m,
   'Checksums the table (issue 388)'
);

($output, $exit_code) = full_output(
   sub { pt_table_checksum::main(
         @args,
         qw(--host 127.1 --port 12345 --user sha256_user),
         qw(--password sha256_user%password --mysql_ssl 1 --mysql_ssl_optional=1),
         qw(-d test)) },
   stderr => 1,
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password with option --mysql_ssl"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error with option --mysql_ssl'
) or diag($output);

unlike(
   $output,
   qr/Use of uninitialized value/,
   'No error (issue 388) with option --mysql_ssl'
);

like(
   $output,
   qr/^\S+\s+0\s+0\s+1\s+0\s+1\s+/m,
   'Checksums the table (issue 388) with option --mysql_ssl'
);

($output, $exit_code) = full_output(
   sub { 
      pt_table_checksum::main(
         @args, 
         'F=t/pt-archiver/samples/pt-191.cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1', 
         qw(-d test),
         "--recursion-method=dsn=F=t/pt-archiver/samples/pt-191.cnf,D=test_ssl,t=dsns,h=127.0.0.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1")
   },
   stderr => 1, 
);

is(
   $exit_code,
   0,
   "No error for SSL options in the configuration file"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error with correct SSL options in the configuration file'
) or diag($output);

($output, $exit_code) = full_output(
   sub { pt_table_checksum::main(@args, 'F=t/pt-archiver/samples/pt-191-error.cnf,h=127.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1', qw(-d test)) },
   stderr => 1,
);

isnt(
   $exit_code,
   0,
   "Error for invalid SSL options in the configuration file"
) or diag($output);

like(
   $output,
   qr/SSL error: key values mismatch/,
   'SSL connection error with incorrect SSL options in the configuration file'
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('source', q/DROP USER 'sha256_user'@'%'/);

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
