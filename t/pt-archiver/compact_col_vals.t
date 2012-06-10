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
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
my $slave_dbh = $sb->get_dbh_for('slave1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 4;
}

my $output;
my $cnf = "/tmp/12345/my.sandbox.cnf";
# Add path to samples to Perl's INC so the tool can find the module.
my $cmd = "perl -I $trunk/t/pt-archiver/samples $trunk/bin/pt-archiver";

# ###########################################################################
# Bulk delete with limit that results in 2 chunks.
# ###########################################################################
$sb->load_file('master', "t/pt-archiver/samples/compact_col_vals.sql");
$dbh->do('use cai');

is_deeply(
   $dbh->selectall_arrayref('select * from `t` order by id'),
   [
      [   1, 'one'                ], 
      [   2, 'two'                ], 
      [   3, 'three'              ], 
      [   4, 'four'               ], 
      [   5, 'five'               ], 
      [   9, 'nine'               ], 
      [  11, 'eleven'             ], 
      [  13, 'thirteen'           ],
      [  14, 'fourteen'           ], 
      [  50, 'fifty'              ], 
      [  51, 'fifty one'          ], 
      [ 200, 'two hundred'        ], 
      [ 300, 'three hundred'      ], 
      [ 304, 'three hundred four' ], 
      [ 305, 'three hundred five' ], 
   ],
   'Table before compacting'
);

`$cmd --purge --no-safe-auto-inc --source F=$cnf,D=cai,t=t,m=compact_col_vals --where "1=1"`;

my $compact_vals = $dbh->selectall_arrayref('select * from `r` order by id');

is_deeply(
   $dbh->selectall_arrayref('select * from `t` order by id'),
   $compact_vals,
   'Compacted values'
);

my $autoinc = $dbh->selectrow_hashref('show table status from `cai` like "t"');
is(
   $autoinc->{auto_increment},
   16,
   "Reset AUTO_INCREMENT"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
