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
    plan tests => 6;
    #plan skip_all => 'This test is taking too much time even in fast machines';
}                                  

our $delay = 15;

my $tmp_file = File::Temp->new();
my $tmp_file_name = $tmp_file->filename;
unlink $tmp_file_name;

require "$trunk/bin/pt-archiver";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh = $sb->get_dbh_for('slave1');
my $master_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my $slave_dsn = 'h=127.0.0.1,P=12346,u=msandbox,p=msandbox';

sub reset_query_cache {
    my @dbhs = @_;
    return if ($sandbox_version >= '8.0');
    foreach my $dbh (@dbhs) {
        $dbh->do('RESET QUERY CACHE');
    }
}

# 1) Set the slave delay to 0 just in case we are re-running the tests without restarting the sandbox.
# 2) Load sample data
# 3) Set the slave delay to 30 seconds to be able to see the 'waiting' message.
diag("Setting slave delay to 0 seconds");
$slave_dbh->do('STOP SLAVE');
$slave_dbh->do('RESET SLAVE');
$slave_dbh->do('START SLAVE');

diag('Loading test data');
$sb->load_file('master', "t/pt-online-schema-change/samples/pt-1898.sql");

my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox test pt178 $num_rows`);

diag("Setting slave delay to $delay seconds");

$slave_dbh->do('STOP SLAVE');
$slave_dbh->do("CHANGE MASTER TO MASTER_DELAY=$delay");
$slave_dbh->do('START SLAVE');

# Run a full table scan query to ensure the slave is behind the master
# There is no query cache in MySQL 8.0+
reset_query_cache($master_dbh, $master_dbh);
$master_dbh->do('UPDATE `test`.`joinit` SET g = g + 1 WHERE g <> 0');

# This is the base test, ust to ensure that without using --check-slave-lag nor --skip-check-slave-lag
# pt-online-schema-change will wait on the slave at port 12346

my $max_lag = $delay / 2;
my @args = ("--source",  "$master_dsn,D=test,t=joinit", "--purge", "--where", "'g < 45'",
           "--commit-each", "--limit", "500", "--statistics", "--check-slave-lag", "h=127.0.0.1,P=12346,u=msandbox,p=msandbox",
           "--max-lag", "1");
diag("Starting base test. This is going to take some time due to the delay in the slave");
diag("pid: $tmp_file_name");
my $argstr = join(@args, " ");
my $output = `$trunk/bin/pt-online-schema-change $argstr 2>&1`;

like(
      $output,
      qr/Replica lag is \d+ seconds on .*  Waiting/s,
      "Base test waits on the correct slave",
);


diag("Setting slave delay to 0 seconds");
$slave_dbh->do('STOP SLAVE');
$slave_dbh->do('RESET SLAVE');
$slave_dbh->do('START SLAVE');

$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
