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
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave2_dbh = $sb->get_dbh_for('slave2');
my $master_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $slave_dsn1 = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';
my $slave_dsn2 = 'h=127.0.0.1,P=12347,u=msandbox,p=msandbox';


sub reset_query_cache {
    my @dbhs = @_;
    return if ($sandbox_version >= '8.0');
    foreach my $dbh (@dbhs) {
        $dbh->do('RESET QUERY CACHE');
    }
}



diag('Loading test data');
$sb->load_file('master', "t/pt-online-schema-change/samples/pt-2241.sql");
# Should be greater than chunk-size and big enough, so pt-osc will wait for delay
my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt2241 $num_rows`);

$sb->wait_for_slaves();
diag("Setting slaves delay to $delay seconds");

$slave1_dbh->do('STOP SLAVE');
$slave1_dbh->do("CHANGE MASTER TO MASTER_DELAY=$delay");
$slave1_dbh->do('START SLAVE');
$slave2_dbh->do('STOP SLAVE');
$slave2_dbh->do("CHANGE MASTER TO MASTER_DELAY=$delay");
$slave2_dbh->do('START SLAVE');

# using --skip-check-slave-lag
# Run a full table scan query to ensure the slave is behind the master
reset_query_cache($master_dbh, $master_dbh);
# Update one row so slave is delayed
$master_dbh->do('UPDATE `test`.`pt2241` SET tcol2 = tcol2 + 1 LIMIT 1');
$master_dbh->do('UPDATE `test`.`pt2241` SET tcol2 = tcol2 + 1 WHERE tcol1 = ""');

# We need to sleep, otherwise pt-osc can finish before slave is delayed
my $max_lag = $delay / 2;
sleep($max_lag);
my $args = "$master_dsn,D=test,t=pt2241 --execute --chunk-size 1 --max-lag $max_lag --alter 'ENGINE=InnoDB' "
      . "--skip-check-slave-lag h=127.0.0.1,P=12346,u=msandbox,p=msandbox,D=test,t=pt2241 --skip-check-slave-lag h=127.0.0.1,P=12347,u=msandbox,p=msandbox,D=test,t=pt2241 --pid $tmp_file_name --progress time,5";

diag("Starting --skip-check-slave-lag test. This is going to take some time due to the delay in the slave");
my $output = `$trunk/bin/pt-online-schema-change $args 2>&1`;

unlike(
      $output,
      qr/Replica lag is \d+ seconds on .*  Waiting/s,
      "--skip-check-slave-lag is really skipping the slave",
);

# #############################################################################
# Done.
# #############################################################################
diag("Setting slave delay to 0 seconds");
$slave1_dbh->do('STOP SLAVE');
$slave2_dbh->do('STOP SLAVE');
$master_dbh->do("RESET MASTER");
$slave1_dbh->do('RESET SLAVE');
$slave1_dbh->do('START SLAVE');
$slave2_dbh->do('RESET SLAVE');
$slave2_dbh->do('START SLAVE');

$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
