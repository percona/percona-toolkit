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
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 644: Another possible infinite loop with mk-table-sync Nibble
# #############################################################################
diag(`/tmp/12345/use < $trunk/t/pt-table-sync/samples/issue_644.sql`);
sleep 1;
$output = `$trunk/bin/pt-table-sync --algo Nibble --sync-to-master h=127.1,P=12346,u=msandbox,p=msandbox -d issue_644 --print --chunk-size 2 -v`;
$output =~ s/\d\d:\d\d:\d\d/00:00:00/g;
ok(
   no_diff(
      $output,
      "t/pt-table-sync/samples/issue_644_output_1.txt",
      cmd_output => 1,
   ),
   'Sync infinite loop (issue 644)'
);

# Thanks to issue 568, this table can be chunked on the char col.
$output = `$trunk/bin/pt-table-sync --algo Chunk --sync-to-master h=127.1,P=12346,u=msandbox,p=msandbox -d issue_644 --print --chunk-size 2 -v`;
$output =~ s/\d\d:\d\d:\d\d/00:00:00/g;
ok(
   no_diff(
      $output,
      "t/pt-table-sync/samples/issue_644_output_2.txt",
      cmd_output => 1,
   ),
   'Sync infinite loop with Chunk algo (issue 644)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
