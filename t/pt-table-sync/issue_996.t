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

my $output;
my @args = ('--sync-to-master', 'h=127.1,P=12346,u=msandbox,p=msandbox',
            qw(-d issue_375 --replicate issue_375.checksums --print));
my $pt_table_checksum = "$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox -d issue_375 --chunk-size 20 --chunk-size-limit 0 --set-vars innodb_lock_wait_timeout=3";

# #############################################################################
# Issue 996: might not chunk inside of mk-table-checksum's boundaries
# #############################################################################

# Re-using this table for this issue.  It has 100 pk rows.
$sb->load_file('master', 't/pt-table-sync/samples/issue_375.sql');
wait_until(
   sub {
      my $row;
      eval {
         $row = $slave_dbh->selectrow_hashref("select * from issue_375.t where id=35");
      };
      return 1 if $row && $row->{foo} eq 'ai';
   },
);

# Make the tables differ.  These diff rows are all in chunk 1.
$slave_dbh->do("update issue_375.t set foo='foo' where id in (21, 25, 35)");
wait_until(
   sub {
      my $row;
      eval {
         $row = $slave_dbh->selectrow_hashref("select * from issue_375.t where id=35");
      };
      return 1 if $row && $row->{foo} eq 'foo';
   },
   0.5, 10,
);

# mk-table-checksum the table with 5 chunks of 20 rows.
$output = `$pt_table_checksum --replicate issue_375.checksums`;
is(
   PerconaTest::count_checksum_results($output, 'diffs'),
   1,
   "Chunk checksum diff"
);

# Run mk-table-sync with the replicate table.  Chunk size here is relative
# to the mk-table-checksum ranges.  So we sub-chunk the 20 row ranges into
# 4 5-row sub-chunks.
my $file = "/tmp/mts-output.txt";
output(
   sub { pt_table_sync::main(@args, qw(--chunk-size 5 -v -v)) },
   file => $file,
);

# The output shows that the 20-row range was chunked into 4 5-row sub-chunks.
$output = `cat $file | grep 'AS chunk_num' | cut -d' ' -f3,4`;
is(
   $output,
"/*issue_375.t:1/5*/ 0
/*issue_375.t:1/5*/ 0
/*issue_375.t:2/5*/ 1
/*issue_375.t:2/5*/ 1
/*issue_375.t:3/5*/ 2
/*issue_375.t:3/5*/ 2
/*issue_375.t:4/5*/ 3
/*issue_375.t:4/5*/ 3
/*issue_375.t:5/5*/ 4
/*issue_375.t:5/5*/ 4
",
   "Chunks within chunk"
);

diag(`rm -rf $file >/dev/null`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
