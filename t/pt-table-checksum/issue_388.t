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
   plan tests => 3;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the tool will die.
# And --max-load "" prevents waiting for status variables.
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = ($master_dsn, qw(--set-vars innodb_lock_wait_timeout=3), '--max-load', ''); 
my $output;

# #############################################################################
# Issue 388: mk-table-checksum crashes when column with comma in the name
# is used in a key
# #############################################################################

$sb->create_dbs($dbh, [qw(test)]);
$sb->load_file('master', 't/lib/samples/tables/issue-388.sql', 'test');

$dbh->do("insert into test.foo values (null, 'john, smith')");

$output = output(
   sub { pt_table_checksum::main(@args, qw(-d test)) },
   stderr => 1,
);

unlike(
   $output,
   qr/Use of uninitialized value/,
   'No error (issue 388)'
);

like(
   $output,
   qr/^\S+\s+0\s+0\s+1\s+1\s+/m,
   'Checksums the table (issue 388)'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
