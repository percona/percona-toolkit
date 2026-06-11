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

# #############################################################################
# Issue 616: mk-table-sync inserts NULL values instead of correct values
# #############################################################################

$sb->load_file('source', "t/lib/samples/issue_616.sql");

output(
   sub { pt_table_sync::main("h=127.1,P=12346,u=msandbox,p=msandbox",
      qw(--sync-to-source --databases issue_616 --execute));
   },
);

$sb->wait_for_replicas();

my $ok_r = [
   [  1, 'from source' ],
   [ 11, 'from source' ],
   [ 21, 'from source' ],
   [ 31, 'from source' ],
   [ 41, 'from source' ],
   [ 51, 'from source' ],
];

my $r = $source_dbh->selectall_arrayref('SELECT * FROM issue_616.t ORDER BY id');
is_deeply(
   $r,
   $ok_r,
   'Issue 616 synced on source'
);
      
$r = $replica_dbh->selectall_arrayref('SELECT * FROM issue_616.t ORDER BY id');
is_deeply(
   $r,
   $ok_r,
   'Issue 616 synced on replica'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
