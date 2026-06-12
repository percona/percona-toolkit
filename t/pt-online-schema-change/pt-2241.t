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

if ($ENV{PERCONA_SLOW_BOX}) {
    plan skip_all => 'This test needs a fast machine';
} else {
    plan tests => 2;
}                                  

our $delay = 30;

my $tmp_file = File::Temp->new();
my $tmp_file_name = $tmp_file->filename;
unlink $tmp_file_name;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1');
my $replica2_dbh = $sb->get_dbh_for('replica2');
my $source_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $replica_dsn1 = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';
my $replica_dsn2 = 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox';


sub reset_query_cache {
    my @dbhs = @_;
    return if ($sandbox_version ge '8.0');
    foreach my $dbh (@dbhs) {
        $dbh->do('RESET QUERY CACHE');
    }
}



diag('Loading test data');
$sb->load_file('source', "t/pt-online-schema-change/samples/pt-2241.sql");
# Should be greater than chunk-size and big enough, so pt-osc will wait for delay
my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt2241 $num_rows`);

$sb->wait_for_replicas();
diag("Setting replicas delay to $delay seconds");

$replica1_dbh->do("STOP ${replica_name}");
$replica1_dbh->do("CHANGE ${source_change} TO ${source_name}_DELAY=$delay");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("CHANGE ${source_change} TO ${source_name}_DELAY=$delay");
$replica2_dbh->do("START ${replica_name}");

# using --skip-check-replica-lag
# Run a full table scan query to ensure the replica is behind the source
reset_query_cache($source_dbh, $source_dbh);
# Update one row so replica is delayed
$source_dbh->do('UPDATE `test`.`pt2241` SET tcol2 = tcol2 + 1 LIMIT 1');
$source_dbh->do('UPDATE `test`.`pt2241` SET tcol2 = tcol2 + 1 WHERE tcol1 = ""');

# We need to sleep, otherwise pt-osc can finish before replica is delayed
my $max_lag = $delay / 2;
sleep($max_lag);
my $args = "$source_dsn,D=test,t=pt2241 --execute --chunk-size 1 --max-lag $max_lag --alter 'ENGINE=InnoDB' "
      . "--skip-check-replica-lag h=127.0.0.1,P=12346,u=msandbox,p=msandbox,D=test,t=pt2241 --skip-check-replica-lag h=127.0.0.1,P=12347,u=msandbox,p=msandbox,D=test,t=pt2241 --pid $tmp_file_name --progress time,5";

diag("Starting --skip-check-replica-lag test. This is going to take some time due to the delay in the replica");
my $output = `$trunk/bin/pt-online-schema-change $args 2>&1`;

unlike(
      $output,
      qr/Replica lag is \d+ seconds on .*  Waiting/s,
      "--skip-check-replica-lag is really skipping the replica",
);

# #############################################################################
# Done.
# #############################################################################
diag("Setting replica delay to 0 seconds");
$replica1_dbh->do("STOP ${replica_name}");
$replica2_dbh->do("STOP ${replica_name}");
$source_dbh->do("RESET ${source_reset}");
$replica1_dbh->do("RESET ${replica_name}");
$replica1_dbh->do("START ${replica_name}");
$replica2_dbh->do("RESET ${replica_name}");
$replica2_dbh->do("START ${replica_name}");

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
