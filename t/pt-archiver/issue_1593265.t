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
$sb->load_file('master', 't/pt-archiver/samples/issue_1593265.sql');

$dbh->do('set names "utf8"');

$output = output(
   sub { pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=test,t=t1,u=msandbox,p=msandbox',
      '--dest', 't=t2', '--where', 'b in (1,2,3)')
   },
);

my $untouched_rows = $dbh->selectall_arrayref('SELECT a, b FROM test.t1');
is_deeply(
   $untouched_rows,
   [ ['10', '5'], ['10', '4'] ],
   "Rows were left on the original table"
);

my $new_rows = $dbh->selectall_arrayref('SELECT a, b FROM test.t2');
is_deeply(
   $new_rows,
   [ ['10', '3'], ['10', '2'], ['10', '1'] ],
   "Rows were archived into the new table"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
