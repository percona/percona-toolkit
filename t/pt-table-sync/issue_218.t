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
require "$trunk/bin/pt-table-sync";

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
else {
   plan tests => 2;
}

$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);

# #############################################################################
# Issue 218: Two NULL column values don't compare properly w/ Stream/GroupBy
# #############################################################################
$sb->create_dbs($source_dbh, [qw(issue218)]);
$sb->use('source', '-e "CREATE TABLE issue218.t1 (i INT)"');
$sb->use('source', '-e "INSERT INTO issue218.t1 VALUES (NULL)"');
$sb->wait_for_replicas();

qx($trunk/bin/pt-table-sync --no-check-replica --print --database issue218 h=127.1,P=12345,u=msandbox,p=msandbox P=12346);
ok(!$?, 'Issue 218: NULL values compare as equal');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
