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

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $dbh = $sb->get_dbh_for('source');
my $replica_dbh = $sb->get_dbh_for('replica1');
my $dsn = $sb->dsn_for("source");

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}
else {
   plan tests => 2;
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;

$sb->load_file('source', "t/pt-online-schema-change/samples/pt-2048.sql");

my $rows_before = $replica_dbh->selectrow_arrayref("select total_connections from performance_schema.users where user like 'msandbox';");

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$dsn,D=test,t=joinit",
            '--execute', '--charset=utf8', '--chunk-size', '2', '--alter', 'engine=innodb',
        ),
    },
    stderr => 1,
);

my $rows_after = $replica_dbh->selectrow_arrayref("select total_connections from performance_schema.users where user like 'msandbox';");

cmp_ok(
   $rows_after->[0] - $rows_before->[0], '<', 10, 
   "pt-2048 reasonable number of connections"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
