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
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
else {
   plan tests => 3;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox,D=pt_1059';
my @args       = ($source_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $output;
my $exit_status;

# We test that checksum works with columns and indexes
# that contain new lines
$sb->load_file('source', 't/pt-table-checksum/samples/pt-1059.sql');
# #############################################################################
# PT-1059 LP #1093972: Tools can't parse index names containing newlines
# #############################################################################

($output, $exit_status) = full_output(
   sub { pt_table_checksum::main(@args, qw(-d pt_1059)) },
   stderr => 1,
);

is(
   PerconaTest::count_checksum_results($output, 'errors'),
   0,
   "Checksum with columns and indexes, containing new lines found no errors"
);

is(
    $exit_status,
    0,
    "Checksum with columns and indexes, containing new lines finished succesfully",
);


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
