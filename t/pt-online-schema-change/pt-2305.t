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

my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my $replica_dsn = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';
my $output;
my $exit_code;
my $sample  = "t/pt-online-schema-change/samples/";

my ($orig_binlog_format) = $source_dbh->selectrow_array(q{SELECT @@global.binlog_format});

$source_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");

($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main("$replica_dsn,D=sakila,t=actor",
      '--alter', 'FORCE', '--execute',
      '--alter-foreign-keys-method', 'auto') }
);

is(
    $exit_code,
    0,
    "pt-online-schema-change run successfully with binlog_format=STATEMENT"
) or diag($output);

like(
    $output,
    qr/Altering `sakila`.`actor`/, 
    "Expected output of pt-online-schema-change with binlog_format=STATEMENT"
) or diag($output);

$source_dbh->do("SET GLOBAL binlog_format = 'ROW'");

($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main("$replica_dsn,D=sakila,t=actor",
      '--alter', 'FORCE', '--execute',
      '--alter-foreign-keys-method', 'auto') }
);

is(
    $exit_code,
    3,
    "pt-online-schema-change failed with binlog_format=ROW"
) or diag($output);

like(
    $output,
    qr/running with binary log format ROW.*Exiting./s, 
    "Expected output of pt-online-schema-change with binlog_format=ROW"
) or diag($output);

($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main("$replica_dsn,D=sakila,t=actor",
      '--alter', 'FORCE', '--execute',
      '--alter-foreign-keys-method', 'auto',
      '--force') }
);

is(
    $exit_code,
    0,
    "pt-online-schema-change run successfully with binlog_format=ROW and --force"
) or diag($output);

like(
    $output,
    qr/Altering `sakila`.`actor`/,
    "Expected output of pt-online-schema-change with binlog_format=ROW and --force"
) or diag($output);

unlike(
    $output,
    qr/running with binary log format ROW.*Exiting./s, 
    "No error for pt-online-schema-change with binlog_format=ROW and --force"
) or diag($output);

$source_dbh->do("SET GLOBAL binlog_format = 'MIXED'");

($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main("$replica_dsn,D=sakila,t=actor",
      '--alter', 'FORCE', '--execute',
      '--alter-foreign-keys-method', 'auto') }
);

is(
    $exit_code,
    3,
    "pt-online-schema-change failed with binlog_format=MIXED"
) or diag($output);

like(
    $output,
    qr/running with binary log format MIXED.*Exiting./s, 
    "Expected output of pt-online-schema-change with binlog_format=MIXED"
) or diag($output);

($output, $exit_code) = full_output(
   sub { pt_online_schema_change::main("$replica_dsn,D=sakila,t=actor",
      '--alter', 'FORCE', '--execute',
      '--alter-foreign-keys-method', 'auto',
      '--force') }
);

is(
    $exit_code,
    0,
    "pt-online-schema-change run successfully with binlog_format=MIXED and --force"
) or diag($output);

like(
    $output,
    qr/Altering `sakila`.`actor`/,
    "Expected output of pt-online-schema-change with binlog_format=MIXED and --force"
) or diag($output);

unlike(
    $output,
    qr/running with binary log format ROW.*Exiting./s, 
    "No error for pt-online-schema-change with binlog_format=MIXED and --force"
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$source_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format}'");
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
