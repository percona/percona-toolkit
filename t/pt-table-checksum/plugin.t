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
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica2_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}

my $output;
my $source_dsn = $sb->dsn_for('source');
my $sample     = "t/pt-table-checksum/samples";
my $plugin     = "$trunk/$sample/plugins";
my $exit;
my $rows;

my ($orig_binlog_format_source) = $source_dbh->selectrow_array(q{SELECT @@global.binlog_format});
my ($orig_binlog_format_replica1) = $replica1_dbh->selectrow_array(q{SELECT @@global.binlog_format});
my ($orig_binlog_format_replica2) = $replica2_dbh->selectrow_array(q{SELECT @@global.binlog_format});

$source_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$source_dbh->do("SET binlog_format = 'STATEMENT'");
$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$replica1_dbh->do("SET binlog_format = 'STATEMENT'");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("SET GLOBAL binlog_format = 'STATEMENT'");
$replica2_dbh->do("SET binlog_format = 'STATEMENT'");
$replica2_dbh->do("START ${replica_name}");

$source_dbh->prepare("drop database if exists percona")->execute();
$source_dbh->prepare("create database percona")->execute();
$source_dbh->prepare("create table if not exists percona.t ( a int primary key);")->execute();
$source_dbh->prepare("insert into percona.t values (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)")->execute();
$source_dbh->prepare("analyze table percona.t;")->execute();

# #############################################################################
# all_hooks.pm
# #############################################################################

($output) = full_output(
   sub { pt_table_checksum::main(
      "$source_dsn",
      '--databases', 'percona',
      '--plugin', "$plugin/all_hooks.pm",
   )},
   stderr => 1,
);

my @called = $output =~ m/^PLUGIN \S+$/gm;

is_deeply(
   \@called,
   [
      'PLUGIN get_replica_lag',
      'PLUGIN init',
      'PLUGIN before_checksum_table',
      'PLUGIN after_checksum_table',
   ],
   "Called all plugins on basic run"
) or diag(Dumper($output));


($output) = full_output(
   sub { pt_table_checksum::main(
      "$source_dsn",
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
$source_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_source}'");
$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_replica1}'");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("SET GLOBAL binlog_format = '${orig_binlog_format_replica2}'");
$replica2_dbh->do("START ${replica_name}");
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
