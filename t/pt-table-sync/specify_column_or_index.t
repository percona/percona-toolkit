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
   plan tests => 3;
}

$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);

# #############################################################################
# Issue 376: Permit specifying an index for pt-table-sync
# #############################################################################
diag(`/tmp/12345/use < $trunk/t/pt-table-sync/samples/issue_375.sql`);
sleep 1;
$output = `$trunk/bin/pt-table-sync --sync-to-source h=127.1,P=12346,u=msandbox,p=msandbox -d issue_375 --print -v -v  --chunk-size 50 --chunk-index updated_at`;
# We cannot rely on the exact time here, because pt-osc uses EXPLAIN to calculate rows range
# and EXPLAIN does not guarantee accuracy of results.
like(
   $output,
   qr/FROM `issue_375`.`t` FORCE INDEX \(`updated_at`\) WHERE \(`updated_at` > 0 AND `updated_at` < '2009-09-05 \d\d:\d\d:\d\d'/,
   '--chunk-index',
) or diag($output);

$output = `$trunk/bin/pt-table-sync --sync-to-source h=127.1,P=12346,u=msandbox,p=msandbox -d issue_375 --print -v -v  --chunk-size 50 --chunk-column updated_at`;
like(
   $output,
   qr/FROM `issue_375`.`t` FORCE INDEX \(`updated_at`\) WHERE \(`updated_at` > 0 AND `updated_at` < '2009-09-05 \d\d:\d\d:\d\d'/,
   '--chunk-column',
) or diag($output);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
