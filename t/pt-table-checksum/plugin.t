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

my $output;
my $master_dsn = $sb->dsn_for('master');
my $sample     = "t/pt-table-checksum/samples";
my $plugin     = "$trunk/$sample/plugins";
my $exit;
my $rows;

$master_dbh->prepare("drop database if exists percona")->execute();
$master_dbh->prepare("create database percona")->execute();
$master_dbh->prepare("create table if not exists percona.t ( a int primary key);")->execute();
$master_dbh->prepare("insert into percona.t values (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)")->execute();
$master_dbh->prepare("analyze table percona.t;")->execute();

# #############################################################################
# all_hooks.pm
# #############################################################################

($output) = full_output(
   sub { pt_table_checksum::main(
      "$master_dsn",
      '--databases', 'percona',
      '--plugin', "$plugin/all_hooks.pm",
   )},
   stderr => 1,
);

my @called = $output =~ m/^PLUGIN \S+$/gm;

is_deeply(
   \@called,
   [
      'PLUGIN get_slave_lag',
      'PLUGIN init',
      'PLUGIN before_checksum_table',
      'PLUGIN after_checksum_table',
   ],
   "Called all plugins on basic run"
) or diag(Dumper($output));


($output) = full_output(
   sub { pt_table_checksum::main(
      "$master_dsn",
      '--replicate-check', '--replicate-check-only',
      '--databases', 'percona',
      '--plugin', "$plugin/all_hooks.pm",
   )},
   stderr => 1,
);

@called = $output =~ m/^PLUGIN \S+$/gm;

is_deeply(
   \@called,
   [
      'PLUGIN before_replicate_check',
      'PLUGIN after_replicate_check',
   ],
   "Called all plugins on replicate-check run"
) or diag(Dumper($output));


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
