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
   plan tests => 4;
}

# #############################################################################
# Issue 634: Cannot nibble table because MySQL chose no index
# #############################################################################
$sb->load_file('source', "t/pt-table-sync/samples/issue_634.sql");
$replica_dbh->do('insert into issue_634.t values (1)');

$output = output(
   sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
      qw(--sync-to-source -d issue_634 --print --execute --algorithms Nibble))
   },
   stderr => 1,
);
$sb->wait_for_replicas();

like(
   $output,
   qr/DELETE FROM `issue_634`.`t` WHERE `i`='1' LIMIT 1/,
   "DELETE statement (issue 634)"
);

unlike(
   $output,
   qr/Cannot nibble/,
   "Doesn't say it can't nibble the 1-row table (issue 634)"
);

is_deeply(
   $replica_dbh->selectall_arrayref('select * from issue_634.t'),
   [],
   '1-row table was synced (issue 634)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
