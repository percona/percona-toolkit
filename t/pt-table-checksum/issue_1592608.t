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
use SqlModes;
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox,D=bug_1592608';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $output;

# We test that checksum works with invalid dates, 
# but for that we need to turn off MySQL's NO_ZERO_IN_DATE mode 
my $modes = new SqlModes($dbh, global=>1);
$modes->del('NO_ZERO_IN_DATE');
$sb->load_file('master', 't/pt-table-checksum/samples/issue_1592608.sql');
# #############################################################################
# Issue 602: mk-table-checksum issue with invalid dates
# #############################################################################

#sub { pt_table_checksum::main(@args, qw(-t issue_1592608.t --tables t )) },
$output = output(
   sub { pt_table_checksum::main(@args, qw(-t t)) },
   stderr => 1,
);

is(
   PerconaTest::count_checksum_results($output, 'rows'),
   1,
   "Large BLOB/TEXT/BINARY Checksum"
);

$modes->restore_original_modes();
# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
