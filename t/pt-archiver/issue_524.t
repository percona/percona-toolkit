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
   plan tests => 2;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";

$sb->create_dbs($dbh, ['test']);

# #############################################################################
# Issue 524: mk-archiver --no-delete --dry-run prints out DELETE statement
# #############################################################################
$sb->load_file('master', 't/pt-archiver/samples/issue_131.sql');
$output = output(
   sub { pt_archiver::main(qw(--where 1=1 --dry-run --no-delete), "--source",  "F=$cnf,D=test,t=issue_131_src", qw(--dest t=issue_131_dst)) },
);
unlike(
   $output,
   qr/DELETE/,
   'No DELETE with --no-delete --dry-run (issue 524)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
