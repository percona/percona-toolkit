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

$ENV{PTTEST_FAKE_TS} = 1;
$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-online-schema-change";
require VersionParser;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $q      = new Quoter();
my $tp     = new TableParser(Quoter => $q);
my @args   = qw(--set-vars innodb_lock_wait_timeout=3);
my $output = "";
my $dsn    = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $exit   = 0;
my $sample = "t/pt-online-schema-change/samples";
my $rows;

# #############################################################################
# Tool shouldn't run without --execute (bug 933232).
# #############################################################################

my ($lower_case_table_names) = $master_dbh->selectrow_array('SELECT @@lower_case_table_names');
plan skip_all => 'MySQL uses case sensitive lookup' if $lower_case_table_names == 0;

$sb->load_file('master', "$sample/basic_no_fks_innodb.sql");

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=T",
      '--alter', 'drop column d', '--execute') }
);

like(
   $output,
   qr/Successfully altered/,
   "Table is altered using capital name 'T'"
) or diag($output);

my $ddl = $master_dbh->selectrow_arrayref("show create table pt_osc.T");
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

$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
