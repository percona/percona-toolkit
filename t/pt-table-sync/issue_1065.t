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

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica1_dbh = $sb->get_dbh_for('replica1'); 
my $replica2_dbh = $sb->get_dbh_for('replica2'); 

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
elsif ( !$replica1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica2';
}
else {
   plan tests => 2;
}

my $output;
my @args = ('--sync-to-source', 'h=127.1,P=12346,u=msandbox,p=msandbox',
            qw(-t test.it1 --print --execute --no-check-triggers));

# #############################################################################
# Issue 1065: mk-table-sync --algorithm seems to be case-sensitive
# #############################################################################
$sb->load_file('source', "t/pt-table-sync/samples/simple-tbls.sql");

$replica1_dbh->do("delete from test.it1 where id=1 limit 1");

$output = output(
   sub { pt_table_sync::main(@args, qw(--algo chunk)) },
);
like(
   $output,
   qr/REPLACE INTO `test`.`it1`/,
   "Case-insensitive --algorithm"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
