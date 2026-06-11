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

require "$trunk/bin/pt-online-schema-change";

plan tests => 3;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for("source");
my $source_dsn = $sb->dsn_for("source");

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;

$sb->load_file('source', "t/pt-online-schema-change/samples/pt-1853.sql");

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$source_dsn,D=test,t=jointit",
            '--execute', 
            '--alter', "engine=innodb",
            '--alter-foreign-keys-method', 'rebuild_constraints'
        ),
    },
    stderr => 1,
);

isnt(
    $exit_status,
    0,
    "PT-1853, there are self-referencing FKs -> exit status != 0",
);

($output, $exit_status) = full_output(
    sub { pt_online_schema_change::main(@args, "$source_dsn,D=test,t=jointit",
            '--execute', 
            '--alter', "engine=innodb",
            '--alter-foreign-keys-method', 'rebuild_constraints',
            '--no-check-foreign-keys'
        ),
    },
    stderr => 1,
);

isnt(
    $exit_status,
    0,
    "PT-1853, there are self-referencing FKs but --no-check-foreign-keys was specified -> exit status = 0",
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
