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
require "$trunk/bin/pt-duplicate-key-checker";

require VersionParser;
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

my $output;
my $sample = "t/pt-duplicate-key-checker/samples/";
my $cnf    = "/tmp/12345/my.sandbox.cnf";
my $cmd    = "$trunk/bin/pt-duplicate-key-checker -F $cnf -h 127.1";

# Testing if we are using DBD::mysql compiled with MariaDB library, which does not support enforcing SSL encryption
$output = `$cmd -d mysql -t columns_priv -v P=12345,u=msandbox,p=msandbox,s=1 2>&1`;

if ( $? == 0 || $output !~ /SSL connection error: Enforcing SSL encryption is not supported/ ) {
   plan skip_all => "Test requires DBD::mysql compiled with MariaDB library that does not support enforcing SSL encryption";
}
elsif ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( $sandbox_version lt '8.0' ) {
   plan skip_all => "Requires MySQL 8.0 or newer";
}

$sb->wipe_clean($dbh);
$sb->create_dbs($dbh, ['test']);

my $transform_int = undef;
# In version 8.0 integer display width is deprecated and not shown in the outputs.
# So we need to transform our samples.
if ($sandbox_version ge '8.0') {
   $transform_int = sub {
      my $txt = slurp_file(shift);
      $txt =~ s/int\(\d{1,2}\)/int/g;
      print $txt;
   };
}

$sb->do_as_root(
   'source',
   q/CREATE USER IF NOT EXISTS sha256_user@'%' IDENTIFIED WITH caching_sha2_password BY 'sha256_user%password' REQUIRE SSL/,
   q/GRANT ALL ON mysql.* TO sha256_user@'%'/,
);

$output = `$cmd -d mysql -t columns_priv -v P=12345,u=sha256_user,p=sha256_user%password,s=0 2>&1`;

isnt(
   $?,
   0,
   "Error raised when SSL connection is not used"
) or diag($output);

like(
   $output,
   qr/Access denied/,
   'Secure connection error raised when no SSL connection used'
) or diag($output);

$output = `$cmd -d mysql -t columns_priv -v P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1`;

is(
   $?,
   0,
   "No error for user, identified with caching_sha2_password"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error'
) or diag($output);

# In version 8.0 order of columns in the index changed
if ($sandbox_version ge '8.0') {
   like($output,
      qr/PRIMARY \(`Host`,`User`,`Db`,`Table_name`,`Column_name`\)/,
      'Finds mysql.columns_priv PK'
   );
} else {
   like($output,
      qr/PRIMARY \(`Host`,`Db`,`User`,`Table_name`,`Column_name`\)/,
      'Finds mysql.columns_priv PK'
   );
}

$output = `$cmd -d mysql -t columns_priv -v --host 127.1 --port 12345 --user sha256_user --password=sha256_user%password --mysql_ssl=1 --mysql_ssl_optional=1`;

is(
   $?,
   0,
   "No error for user, identified with caching_sha2_password with option --mysql_ssl=1 --mysql_ssl_optional=1"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error with option --mysql_ssl=1 --mysql_ssl_optional=1'
) or diag($output);

# In version 8.0 order of columns in the index changed
if ($sandbox_version ge '8.0') {
   like($output,
      qr/PRIMARY \(`Host`,`User`,`Db`,`Table_name`,`Column_name`\)/,
      'Finds mysql.columns_priv PK with option --mysql_ssl=1 --mysql_ssl_optional=1'
   );
} else {
   like($output,
      qr/PRIMARY \(`Host`,`Db`,`User`,`Table_name`,`Column_name`\)/,
      'Finds mysql.columns_priv PKi with option --mysql_ssl=1 --mysql_ssl_optional=1'
   );
}

$output = `$cmd -d mysql -t columns_priv -v F=t/pt-archiver/samples/pt-191.cnf,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1 2>&1`;

is(
   $?,
   0,
   "No error for SSL options in the configuration file"
) or diag($output);

unlike(
   $output,
   qr/Access denied/,
   'No secure connection error with correct SSL options in the configuration file'
) or diag($output);

$output = `$cmd -d mysql -t columns_priv -v F=t/pt-archiver/samples/pt-191-error.cnf,P=12345,u=sha256_user,p=sha256_user%password,s=1,o=1 2>&1`;

isnt(
   $?,
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
done_testing;
