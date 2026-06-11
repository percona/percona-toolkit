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
use Time::HiRes qw(sleep);

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-online-schema-change";
require VersionParser;

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

my @args   = qw(--set-vars innodb_lock_wait_timeout=3);
my $output = "";
my $dsn    = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $exit   = 0;
my $sample = "t/pt-online-schema-change/samples";

my $lower_case_table_names = $source_dbh->selectrow_array('SELECT @@lower_case_table_names');

if ( $lower_case_table_names == 0) {
   # Preparing test setup on Linux
   diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
   diag(`EXTRA_DEFAULTS_FILE="$trunk/t/pt-online-schema-change/samples/lower_case_table_names_1.cnf" $trunk/sandbox/start-sandbox source 12348 >/dev/null`);

   $source_dbh = $sb->get_dbh_for('source1');
   $dsn    = "h=127.1,P=12348,u=msandbox,p=msandbox";
   $sb->load_file('source1', "$sample/basic_no_fks_innodb.sql");
} else {
   $sb->load_file('source', "$sample/basic_no_fks_innodb.sql");
}

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=T",
      '--alter', 'drop column d', '--execute') }
);

like(
   $output,
   qr/Successfully altered/,
   "Table is altered using capital name 'T'"
) or diag($output);

my $ddl = $source_dbh->selectrow_arrayref("show create table pt_osc.T");
unlike(
   $ddl->[1],
   qr/^\s+["`]d["`]/m,
   "'D' column is dropped"
);

is(
   $exit,
   0,
   "Exit 0"
);

# #############################################################################
# Done.
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
$source_dbh = $sb->get_dbh_for('source');
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
