#!/usr/bin/env perl

BEGIN {
    die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
    unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
    unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;
use threads::shared;
use Thread::Semaphore;

use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir /;

if ($sandbox_version lt '5.7') {
    plan skip_all => 'This test needs MySQL 5.7+';
} else {
    plan tests => 2;
}    

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $dbh = $sb->get_dbh_for('source');
my $dsn = $sb->dsn_for("source");

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;

$sb->load_file('source', "t/pt-online-schema-change/samples/pt-1528.sql");

my $rows_before = $dbh->selectall_hashref("SELECT * FROM test.brokenutf8alter", "id");

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$dsn,D=test,t=brokenutf8alter",
            '--execute', '--charset=utf8', '--chunk-size', '2', '--alter', 'engine=innodb',
        ),
    },
    stderr => 1,
);

my $rows_after = $dbh->selectall_hashref("SELECT * FROM test.brokenutf8alter", "id");

is_deeply(
    $rows_before, 
    $rows_after,
    "Should be equal",
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
