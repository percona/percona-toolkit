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

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";
my $cmd = "$trunk/bin/pt-archiver";

# ###########################################################################
# Test the custom plugin gt_n.
# ###########################################################################
$sb->load_file('master', 't/pt-archiver/samples/gt_n.sql');
my $sql = 'select status, count(*) from gt_n.t1 group by status';
is_deeply(
   $dbh->selectall_arrayref($sql),
   [
      [qw(bad 7)],
      [qw(ok 12)],
   ],
   'gt_n.t has 12 ok before archive'
);

# Add path to samples to Perl's INC so the tool can find the module.
diag(`perl -I $trunk/t/pt-archiver/samples $cmd --where '1=1' --purge --source F=$cnf,D=gt_n,t=t1,m=gt_n 2>&1`);

is_deeply(
   $dbh->selectall_arrayref($sql),
   [
      [qw(bad 1)],
      [qw(ok 5)],
   ],
   'gt_n.t has max 5 ok after archive'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
