#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;

use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir tempfile /;

our $delay = 10; 

my $tmp_file = File::Temp->new();
my $tmp_file_name = $tmp_file->filename;
unlink $tmp_file_name;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
if ($sb->is_cluster_mode) {
    plan skip_all => 'Not for PXC';
}

my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh1 = $sb->get_dbh_for('replica1');
my $replica_dbh2 = $sb->get_dbh_for('replica2');
my $source_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $replica_dsn1 = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';
my $replica_dsn2 = 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox';
my $sample = "t/pt-online-schema-change/samples";
my ($orig_master_info_repository, $orig_relay_log_info_repository);
if ( $sandbox_version lt '8.4' ) {
   ($orig_master_info_repository) = $replica_dbh1->selectrow_array(q{SELECT @@master_info_repository});
   ($orig_relay_log_info_repository) = $replica_dbh1->selectrow_array(q{SELECT @@relay_log_info_repository});
}

$replica_dbh1->do("stop ${replica_name}");
$replica_dbh1->do("reset ${replica_name} all");
if ( $sandbox_version lt '8.4' ) {
   $replica_dbh1->do("SET GLOBAL master_info_repository='TABLE'");
   $replica_dbh1->do("SET GLOBAL relay_log_info_repository='TABLE'");
}
$replica_dbh1->do("CHANGE ${source_change} TO ${source_name}_HOST='127.0.0.1', ${source_name}_PORT=12345, ${source_name}_USER = 'msandbox', ${source_name}_PASSWORD='msandbox' FOR CHANNEL 'channel1';");
$replica_dbh1->do("start ${replica_name}");

diag('Loading test data');
$sb->load_file('source', "t/pt-online-schema-change/samples/replica_lag.sql");
my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt178 $num_rows`);

my $output = output(
   sub { pt_online_schema_change::main("$source_dsn,D=test,t=pt178,s=1",
         '--execute', 
         '--alter', "force",
         '--recurse', '1',
         '--max-lag', '2',
         '--channel', 'channel1')
      },  
);

like(
   $output,
   qr/Successfully altered `test`.`pt178`/s,
   'pt-osc completes successfully when replication channel used',
);

# #############################################################################
# Done.
# #############################################################################
$replica_dbh1->do("STOP ${replica_name}");
$source_dbh->do("RESET ${source_reset}");
$replica_dbh1->do("RESET ${replica_name} ALL");
if ( $sandbox_version lt '8.4' ) {
   $replica_dbh1->do("SET GLOBAL master_info_repository='${orig_master_info_repository}'");
   $replica_dbh1->do("SET GLOBAL relay_log_info_repository='${orig_relay_log_info_repository}'");
}
$replica_dbh1->do("CHANGE ${source_change} TO ${source_name}_HOST='127.0.0.1', ${source_name}_PORT=12345, ${source_name}_USER = 'msandbox', ${source_name}_PASSWORD='msandbox';");
$replica_dbh1->do("START ${replica_name}");

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

