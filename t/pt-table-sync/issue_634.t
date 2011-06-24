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

use MaatkitTest;
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
   plan tests => 2;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 634: Cannot nibble table because MySQL chose no index
# #############################################################################
diag(`/tmp/12345/use < $trunk/t/pt-table-sync/samples/issue_634.sql`);
$slave_dbh->do('insert into issue_634.t values (1)');
$output = `$trunk/bin/pt-table-sync --sync-to-master h=127.1,P=12346,u=msandbox,p=msandbox -d issue_634 --execute --algorithms Nibble 2>&1`;
unlike(
   $output,
   qr/Cannot nibble/,
   "Doesn't say it can't nibble the 1-row table (issue 634)"
);
is_deeply(
   $slave_dbh->selectall_arrayref('select * from issue_634.t'),
   [],
   '1-row table was synced (issue 634)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
