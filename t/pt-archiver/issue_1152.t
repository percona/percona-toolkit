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

# This issue/bug seems not to have been reproduced or followed up on.
plan skip_all => "issue 1152";

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";

$sb->load_file('master', 't/pt-archiver/samples/issue_1152.sql');

# #############################################################################
# Issue 1152: mk-archiver columns option resulting in null archived table data
# #############################################################################

$output = output(
   sub { pt_archiver::main(
      qw(--header --progress 1000 --statistics --limit 1000),
      qw(--commit-each --why-quit),
      '--source',  'h=127.1,P=12345,D=issue_1152,t=t,u=msandbox,p=msandbox',
      '--dest',    'h=127.1,P=12345,D=issue_1152_archive,t=t',
      '--columns', 'a,b,c',
      '--where',   'id = 5')},
);
ok(1, "Issue 1152 test stub");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
