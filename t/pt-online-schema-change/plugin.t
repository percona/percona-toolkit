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

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
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
# all_hooks.pm
# #############################################################################

($output) = full_output(
   sub { pt_online_schema_change::main(
      "$master_dsn,D=pt_osc,t=t",
      '--plugin', "$plugin/all_hooks.pm",
      qw(--statistics --execute),
   )},
   stderr => 1,
);

my @called = $output =~ m/^PLUGIN \S+$/gm;

is_deeply(
   \@called,
   [
      'PLUGIN get_slave_lag',
      'PLUGIN init',
      'PLUGIN before_create_new_table',
      'PLUGIN after_create_new_table',
      'PLUGIN before_alter_new_table',
      'PLUGIN after_alter_new_table',
      'PLUGIN before_create_triggers',
      'PLUGIN after_create_triggers',
      'PLUGIN before_copy_rows',
      'PLUGIN after_copy_rows',
      'PLUGIN before_swap_tables',
      'PLUGIN after_swap_tables',
      'PLUGIN before_drop_old_table',
      'PLUGIN after_drop_old_table',
      'PLUGIN before_drop_triggers',
      'PLUGIN before_exit'
   ],
   "Called all plugins on basic run"
) or diag(Dumper(\@called));

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
