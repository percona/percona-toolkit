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
   plan tests => 4;
}

$sb->load_file('master', 't/pt-table-checksum/samples/PT-173.sql');
# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = $sb->dsn_for('master');
my @args       = ($master_dsn, "--resume", "--truncate-replicate-table"); 
my $output;
my $exit_status;

# Test #1 
$output = output(
   sub { $exit_status = pt_table_checksum::main(@args) },
   stderr => 1,
);

isnt(
   $exit_status,
   0,
   "Cannot use --resume with --truncate-replicate-table",
);

# Test #2 
@args       = ($master_dsn, "--truncate-replicate-table"); 
$output = output(
   sub { $exit_status = pt_table_checksum::main(@args) },
   stderr => 1,
);

my $row = $dbh->selectrow_arrayref('select count(*) from percona.checksums where `db` = "fake_db"');

is(
   $row->[0],
   0,
   "--truncate-replicate-table replicate table has been truncated",
);

# Test #3 
$sb->load_file('master', 't/pt-table-checksum/samples/PT-173.sql');

@args       = ($master_dsn, "--truncate-replicate-table", "--empty-replicate-table"); 
$output = output(
   sub { $exit_status = pt_table_checksum::main(@args) },
   stderr => 1,
);

$row = $dbh->selectrow_arrayref('select count(*) from percona.checksums where `db` = "fake_db"');
is(
   $row->[0],
   0,
   "--truncate-replicate-table has precedence over --empty-replicate-table",
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
