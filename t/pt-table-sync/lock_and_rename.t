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

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( VersionParser->new($master_dbh) < '5.5' ) {
   plan skip_all => "This functionality doesn't work correctly on MySQLs earlier than 5.5";
}
if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 3;
}

# #############################################################################
# Issue 363: lock and rename.
# #############################################################################
$sb->create_dbs($master_dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-sync/samples/before.sql');

$output = `$trunk/bin/pt-table-sync --lock-and-rename h=127.1,P=12345 P=12346 2>&1`;
like($output, qr/requires exactly two/,
   '--lock-and-rename error when DSNs do not specify table');

# It's hard to tell exactly which table is which, and the tables are going
# to be "swapped", so we'll put a marker in each table to test the swapping.
`/tmp/12345/use -e "alter table test.test1 comment='test1'"`;

$output = `$trunk/bin/pt-table-sync --execute --lock-and-rename h=127.1,P=12345,u=msandbox,p=msandbox,D=test,t=test1 t=test2 2>&1`;
diag $output if $output;

$output = `/tmp/12345/use -e 'show create table test.test2'`;
like($output, qr/COMMENT='test1'/, '--lock-and-rename worked');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
