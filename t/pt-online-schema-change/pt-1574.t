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
    plan tests => 5;
}    

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $dbh = $sb->get_dbh_for('master');
my $dsn = $sb->dsn_for("master");

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;

$sb->load_file('master', "t/pt-online-schema-change/samples/pt-1574.sql");

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$dsn,D=test,t=t1",
            '--execute', "--chunk-index", "idx_id", "--chunk-size", "1", 
            "--nocheck-plan", '--alter', "engine=innodb",
        ),
    },
    stderr => 1,
);

my $sql_mode = $dbh->selectcol_arrayref('SELECT @@sql_mode');
warn Data::Dumper::Dumper($sql_mode);

isnt(
    $exit_status,
    0,
    "PT-1574, PT-1590 There is no unique index exit status",
);

like(
    $output,
    qr/at least one UNIQUE and NOT NULLABLE index/s,
    "PT-1574, PT-1590 Message you need an unique index.",
);

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$dsn,D=test,t=t2",
            '--execute', "--chunk-index", "idx_id", "--chunk-size", "1", 
            "--nocheck-plan", '--alter', "engine=innodb",
        ),
    },
    stderr => 1,
);

is(
    $exit_status,
    0,
    "PT-1574, PT-1590 Exit status 0 with null fields",
);

like(
    $output,
    qr/Successfully altered `test`.`t2`/s,
    "PT-1574, PT-1590 Successfully altered `test`.`t2`",
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
