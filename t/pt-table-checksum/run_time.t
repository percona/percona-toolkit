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
use Time::HiRes qw(time);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $output;
my $exit_status;

# On my 2.4 GHz with SSD this takes a little more than 5s,
# so no test servers should be faster, hopefully.
my $t0 = time;
$exit_status = pt_table_checksum::main(@args,
   qw(--quiet --quiet -d sakila --chunk-size 50 --run-time 1));
my $t  = time - $t0;

ok(
   $t >= 1.0 && $t <= 2.5,
   "Ran in roughly --run-time 1 second"
) or diag("Actual run time: $t");

my $rows = $master_dbh->selectall_arrayref("SELECT DISTINCT CONCAT(db, '.', tbl) FROM percona.checksums ORDER by db, tbl");
my $sakila_finished = grep { $_->[0] eq 'sakila.store' } @$rows;
ok(
   !$sakila_finished,
   "Did not finish checksumming sakila"
) or diag(Dumper($rows));

# Add --resume to complete the run.
$exit_status = pt_table_checksum::main(@args,
   qw(--quiet --quiet -d sakila --chunk-size 100));

$rows = $master_dbh->selectall_arrayref("SELECT DISTINCT CONCAT(db, '.', tbl) FROM percona.checksums ORDER by db, tbl");
$sakila_finished = grep { $_->[0] eq 'sakila.store' } @$rows;
ok(
   $sakila_finished,
   "Resumed and finish checksumming sakila"
) or diag(Dumper($rows));

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
