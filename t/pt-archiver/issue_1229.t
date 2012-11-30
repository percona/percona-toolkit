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
use Data::Dumper;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( $DBD::mysql::VERSION lt '4' ) {
   plan skip_all => "DBD::mysql version $DBD::mysql::VERSION has utf8 bugs. "
	. "See https://bugs.launchpad.net/percona-toolkit/+bug/932327";
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

$dbh->do('set names "utf8"');
my $original_rows = $dbh->selectall_arrayref('select c from issue_1225.t where i in (1, 2)');
is_deeply(
   $original_rows,
   [  [ 'が'],  # Your terminal must be UTF8 to see this Japanese character.
      [ 'が'],
   ],
   "Inserted UTF8 data"
) or diag(Dumper($original_rows));

diag(`rm -rf $file >/dev/null`);

$output = output(
   sub { pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=issue_1225,t=t,u=msandbox,p=msandbox',
      '--file',    $file,
      qw(--where 1=1 -A UTF8)) # -A utf8 makes it work
   },
   stderr => 1,
);

my $got   = slurp_file($file);
$got =~ s/^\d+//gsm;
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
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
