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
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 3;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);

# #############################################################################
# Issue 376: Permit specifying an index for mk-table-sync
# #############################################################################
diag(`/tmp/12345/use < $trunk/t/pt-table-sync/samples/issue_375.sql`);
sleep 1;
$output = `$trunk/bin/pt-table-sync --sync-to-master h=127.1,P=12346,u=msandbox,p=msandbox -d issue_375 --print -v -v  --chunk-size 50 --chunk-index updated_at`;
like(
   $output,
   qr/FROM `issue_375`.`t` FORCE INDEX \(`updated_at`\) WHERE \(`updated_at` > 0 AND `updated_at` < '2009-09-05 02:38:12'/,
   '--chunk-index',
);

$output = `$trunk/bin/pt-table-sync --sync-to-master h=127.1,P=12346,u=msandbox,p=msandbox -d issue_375 --print -v -v  --chunk-size 50 --chunk-column updated_at`;
like(
   $output,
   qr/FROM `issue_375`.`t` FORCE INDEX \(`updated_at`\) WHERE \(`updated_at` > 0 AND `updated_at` < '2009-09-05 02:38:12'/,
   '--chunk-column',
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
