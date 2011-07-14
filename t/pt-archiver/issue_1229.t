#!/usr/bin/env perl
# test 'x'
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
   plan tests => 2;
}

my $output;
my $rows;
my $cnf  = "/tmp/12345/my.sandbox.cnf";
my $file = "/tmp/mk-archiver-file.txt";

# #############################################################################
# Issue 1229: mk-archiver not creating UTF8 compatible file handles for
# archive to file
# #############################################################################
$sb->load_file('master', 't/pt-archiver/samples/issue_1225.sql');
PerconaTest::wait_for_table($dbh, 'issue_1225.t');

$dbh->do('set names "utf8"');
my $original_rows = $dbh->selectall_arrayref('select * from issue_1225.t where i in (1, 2)');
is_deeply(
   $original_rows,
   [  [ 1, 'が'],  # Your terminal must be UTF8 to see this Japanese character.
      [ 2, 'が'],
   ],
   "Inserted UTF8 data"
);

diag(`rm -rf $file >/dev/null`);

$output = output(
   sub { pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=issue_1225,t=t,u=msandbox,p=msandbox',
      '--file',    $file,
      qw(--where 1=1 -A UTF8)) # -A utf8 makes it work
   },
   stderr => 1,
);

my $got = `cat $file`;
ok(
   no_diff(
      $got,
      "t/pt-archiver/samples/issue_1229_file.txt",
      cmd_output => 1,
   ),
   "Printed UTF8 data to --file"
);

diag(`rm -rf $file >/dev/null`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
