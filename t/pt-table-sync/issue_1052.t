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

my $output;
my @args = ('--sync-to-source', 'h=127.1,P=12346,u=msandbox,p=msandbox',
            qw(-d issue_1052 --print));

# #############################################################################
# Issue 1052: mk-table-sync inserts "0x" instead of "" for empty varchar column
# #############################################################################

# Re-using this table for this issue.  It has 100 pk rows.
$sb->load_file('source', 't/pt-table-sync/samples/issue_1052.sql');
wait_until(
   sub {
      my $row;
      eval {
         $row = $replica_dbh->selectrow_hashref("select * from issue_1052.t");
      };
      return 1 if $row;
   },
);

$output = output(
   sub { pt_table_sync::main(@args) },
   trf => \&remove_traces,
);

is(
   $output,
"REPLACE INTO `issue_1052`.`t`(`opt_id`, `value`, `option`, `desc`) VALUES ('2', '', 'opt2', 'something else');
",
   "Insert '' for blank varchar"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
