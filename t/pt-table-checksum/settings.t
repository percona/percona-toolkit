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

if ( $sandbox_version lt '5.6' ) {
   plan skip_all => 'Tests for MySQL 5.6';
}

diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
diag(`EXTRA_DEFAULTS_FILE="$trunk/t/pt-table-checksum/samples/explicit_defaults_for_timestamp.cnf" $trunk/sandbox/start-sandbox master 12348 >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master 12348';
}

my $master_dsn = 'h=127.1,P=12348,u=msandbox,p=msandbox';
my @args       = ($master_dsn, '--max-load', ''); 
my $output;
my $retval;

$output = output(
   sub { $retval = pt_table_checksum::main(@args, qw(-t mysql.user)) },
   stderr => 1,
);

unlike(
   $output,
   qr/error 1364/i,
   "explicit_defaults_for_timestamp (bug 1163735): no error"
);

# Exit will be non-zero because of "Diffs cannot be detected because
# no slaves were found."

# #############################################################################
# Done.
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
