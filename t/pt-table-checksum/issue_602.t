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
$sb->load_file('master', 't/pt-table-checksum/samples/issue_602.sql');

# #############################################################################
# Issue 602: mk-table-checksum issue with invalid dates
# #############################################################################

$output = output(
   sub {
      pt_table_checksum::main("F=$cnf", qw(-t issue_602.t --chunk-size 5)) },
   stderr => 1,
);

like(
   $output,
   qr/^issue_602\s+t\s+2/m,
   "Checksums table despite invalid datetime"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
