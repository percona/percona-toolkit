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
# Issue 560: mk-table-sync generates impossible WHERE
# #############################################################################
$sb->load_file("source", "t/pt-table-sync/samples/issue_560.sql");

# Make replica differ.
$replica_dbh->do('UPDATE issue_560.buddy_list SET buddy_id=0 WHERE player_id IN (333,334)');
$replica_dbh->do('UPDATE issue_560.buddy_list SET buddy_id=0 WHERE player_id=486');

$output = `$trunk/bin/pt-table-checksum --replicate issue_560.checksum h=127.1,P=12345,u=msandbox,p=msandbox  -d issue_560 --chunk-size 50 --set-vars innodb_lock_wait_timeout=3`;

is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   2,
   'Found checksum differences (issue 560)'
);

$output = output(
   sub { pt_table_sync::main('--sync-to-source', 'h=127.1,P=12346,u=msandbox,p=msandbox', qw(-d issue_560 --print -v -v  --chunk-size 50 --replicate issue_560.checksum)) },
   trf => \&remove_traces,
);
$output =~ s/\d\d:\d\d:\d\d/00:00:00/g;
ok(
   no_diff(
      $output,
      "t/pt-table-sync/samples/issue_560_output_2.txt",
      cmd_output => 1,
   ),
   'Sync only --replicate chunks'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
$sb->wipe_clean($replica_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
