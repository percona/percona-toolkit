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

$dbh->do("DROP TABLE IF EXISTS percona.checksums");
$sb->load_file('master', 't/pt-table-checksum/samples/pt-136.sql');
$sb->wait_for_slaves();
my $master_dsn = $sb->dsn_for('master');
my @args       = ($master_dsn, '--databases', 'db1', '--no-replicate-check'); 
my $output;
my $exit_status;

$output = output(
   sub { $exit_status = pt_table_checksum::main(@args) },
   stderr => 1,
);

is(
   $exit_status,
   0,
   "Checksum columns with mismatching collations",
) or BAIL_OUT("debug time");


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
