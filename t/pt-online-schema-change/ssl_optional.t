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
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my $source_dsn = 'h=127.1,P=12345';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_code;
my $sample  = "t/pt-online-schema-change/samples/";

# Testing if we are using DBD::mysql compiled with MariaDB library, which does not support enforcing SSL encryption
($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=sakila,t=actor,u=msandbox,p=msandbox,s=1",
      "--alter", "force",
      "--alter-foreign-keys-method", "auto",
      qw(--dry-run --no-check-alter)),
   },
   stderr => 1,
);

if ( $exit_code == 0 || $output !~ /SSL connection error: Enforcing SSL encryption is not supported/ ) {
   plan skip_all => "Test requires DBD::mysql compiled with MariaDB library that does not support enforcing SSL encryption";
}

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT ALL ON test.* TO sha256_user@'%'/,
   q/GRANT SELECT ON test_ssl.* TO sha256_user@'%'/,
   q/GRANT REPLICATION SLAVE ON *.* TO sha256_user@'%'/,
   q/GRANT SUPER ON *.* TO sha256_user@'%'/,
);

# #############################################################################
# DROP PRIMARY KEY
# #############################################################################

$sb->load_file('source', "$sample/del-trg-bug-1103672.sql");
$sb->load_file('source', "$sample/ssl_dsns.sql");

($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=test,t=t1,u=sha256_user,p=sha256_user%password,s=0",
      "--alter", "drop primary key, add column _id int unsigned not null primary key auto_increment FIRST",
      qw(--execute --no-check-alter)),
   },
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
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=test,t=t1,u=sha256_user,p=sha256_user%password,s=1,o=1",
      "--alter", "drop primary key, add column _id int unsigned not null primary key auto_increment FIRST",
      qw(--execute --no-check-alter)),
   },
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
   qr/Successfully altered `test`.`t1`/,
   "DROP PRIMARY KEY"
);

# Restoring environment for the new test
$sb->load_file('source', "$sample/del-trg-bug-1103672.sql");

($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=test,t=t1",
      qw(--user sha256_user --password sha256_user%password --mysql_ssl_optional 1 --mysql_ssl 1),
      "--alter", "drop primary key, add column _id int unsigned not null primary key auto_increment FIRST",
      qw(--execute --no-check-alter)),
   },
);

is(
   $exit_code,
   0,
   "No error for user, identified with caching_sha2_password with option --mysql_ssl_optional 1 --mysql_ssl"
) or diag($output);

unlike(
   $output,
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with option --mysql_ssl_optional 1 --mysql_ssl'
) or diag($output);

like(
   $output,
   qr/Successfully altered `test`.`t1`/,
   "DROP PRIMARY KEY with option --mysql_ssl_optional 1 --mysql_ssl"
);

# Restoring environment for the new test
$sb->load_file('source', "$sample/del-trg-bug-1103672.sql");

($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,F=t/pt-archiver/samples/pt-191.cnf,D=test,t=t1,u=sha256_user,p=sha256_user%password,s=1,o=1",
      "--alter", "drop primary key, add column _id int unsigned not null primary key auto_increment FIRST",
      qw(--execute --no-check-alter),
      "--recursion-method=dsn=F=t/pt-archiver/samples/pt-191.cnf,D=test_ssl,t=dsns,h=127.0.0.1,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1"),
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
   qr/Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection./,
   'No secure connection error with correct SSL options in the configuration file'
) or diag($output);

($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main(@args,
      "F=$trunk/t/pt-archiver/samples/pt-191-error.cnf,$source_dsn,D=test,t=t1,u=sha256_user,p=sha256_user%password,s=1,o=1",
      "--alter", "drop primary key, add column _id int unsigned not null primary key auto_increment FIRST",
      qw(--execute --no-check-alter)),
   },
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

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
