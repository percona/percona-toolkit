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

# #############################################################################
# Issue 1152: mk-archiver columns option resulting in null archived table data
# #############################################################################
$sb->load_file('master', 't/pt-archiver/samples/pt-143.sql');

my $original_rows = $dbh->selectall_arrayref('select * from test.stats_r');
my $exit_status;

$output = output(
   sub { $exit_status = pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=test,t=stats_r,u=msandbox,p=msandbox',
      '--dest', 'D=test,t=stats_s',
      qw(--where 1=1 --purge))
   },
);

is (
    $exit_status,
    0,
    "PT-143 exit status OK",
);

my $archived_rows = $dbh->selectall_arrayref('select * from test.stats_s');

is_deeply(
   $original_rows,
   $archived_rows,
   "PT-143 Archived rows match original rows"
);

$dbh->do('DROP DATABASE test');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
