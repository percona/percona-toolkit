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

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-table-checksum";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 1;
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';
$sb->create_dbs($dbh, [qw(test)]);
$sb->load_file('master', 't/pt-table-checksum/samples/checksum_tbl.sql');

# #############################################################################
# Issue 1020: mk-table-checksum should not checksum with --replicate-check=0
# #############################################################################

$output = output(
   sub { pt_table_checksum::main("F=$cnf", qw(--replicate=test.checksum --replicate-check=0)) },
   stderr => 1,
);

is (
   $output,
   '',
   "mk-table-checksum should not checksum with --replicate-check=0 (issue 1020)"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
