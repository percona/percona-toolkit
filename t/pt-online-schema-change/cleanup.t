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
require "$trunk/bin/pt-online-schema-change";
require VersionParser;

use Time::HiRes qw(sleep);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');
my $dbh2 = $sb->get_dbh_for('master');

if ( !$dbh1 || !$dbh2 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( $sandbox_version lt '5.5' ) {
   plan skip_all => "Metadata locks require MySQL 5.5 and newer";
}

my $output;
my $master_dsn = $sb->dsn_for('master');
my $sample     = "t/pt-online-schema-change/samples";
my $plugin     = "$trunk/$sample/plugins";
my $exit;
my $rows;

# Loads pt_osc.t with cols id (pk), c (unique index),, d.
$sb->load_file('master', "$sample/basic_no_fks_innodb.sql");

# #############################################################################
# Meta-block on create_triggers.
# #############################################################################

($output) = full_output(
   sub { pt_online_schema_change::main(
      "$master_dsn,D=pt_osc,t=t",
      qw(--statistics --execute --tries drop_triggers:1:0.01),
      qw(--set-vars lock_wait_timeout=1 --print --no-swap-tables),
      '--plugin', "$plugin/make_drop_trigger_fail.pm",
   )},
   stderr => 1,
);

my $triggers = $dbh1->selectall_arrayref("SHOW TRIGGERS FROM pt_osc");
is(
   @$triggers,
   3,
   "Bug 1188002: triggers not dropped"
) or diag(Dumper($triggers));

my $tables = $dbh1->selectall_arrayref("SHOW TABLES FROM pt_osc");
is_deeply(
   $tables,
   [ ['_t_new'], ['t'] ],
   "Bug 1188002: new table not dropped"
) or diag(Dumper($tables));

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
