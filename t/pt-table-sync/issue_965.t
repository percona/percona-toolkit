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
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

my $output;

# #############################################################################
# Issue 965: mk-table-sync --trim can cause impossible WHERE, invalid SQL
# #############################################################################
$sb->wipe_clean($dbh);
$sb->load_file('master', 't/pt-table-sync/samples/issue_965.sql');

$output = output(
   sub {
      pt_table_sync::main(qw(--trim --print --execute -F /tmp/12345/my.sandbox.cnf),
         'D=issue_965,t=t1', 'D=issue_965,t=t2')
   },
   trf => \&remove_traces,
);

is(
   $output,
"DELETE FROM `issue_965`.`t2` WHERE `b_ref`='aae' AND `r`='5' AND `o_i`='100' LIMIT 1;
INSERT INTO `issue_965`.`t2`(`b_ref`, `r`, `o_i`, `r_s`) VALUES ('aae', '5', '1', '2010-03-29 14:44:00');
",
   "Correct SQL statements"
);

is_deeply(
   $dbh->selectall_arrayref('select o_i from issue_965.t2 where b_ref="aae"'),
   [[1]],
   'Synced 2nd table'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
