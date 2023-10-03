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

my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh1 = $sb->get_dbh_for('slave1');
my $slave_dbh2 = $sb->get_dbh_for('slave2');
my $master_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $slave_dsn1 = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';
my $slave_dsn2 = 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox';
my $sample = "t/pt-online-schema-change/samples";

$slave_dbh1->do("stop slave");
$slave_dbh1->do("reset slave all");
$slave_dbh1->do("CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=12345, MASTER_USER = 'msandbox', MASTER_PASSWORD='msandbox' FOR CHANNEL 'channel1';");
$slave_dbh1->do("start slave");

diag('Loading test data');
$sb->load_file('master', "t/pt-online-schema-change/samples/slave_lag.sql");
my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt178 $num_rows`);

my $output = output(
   sub { pt_online_schema_change::main("$master_dsn,D=test,t=pt178",
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
$slave_dbh1->do('STOP SLAVE');
$master_dbh->do("RESET MASTER");
$slave_dbh1->do('RESET SLAVE ALL');
$slave_dbh1->do("CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=12345, MASTER_USER = 'msandbox', MASTER_PASSWORD='msandbox';");
$slave_dbh1->do('START SLAVE');

$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;

