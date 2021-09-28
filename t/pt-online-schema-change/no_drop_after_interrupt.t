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

use File::Temp qw/ tempfile /;
use Time::HiRes qw(sleep);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $table = "t";
my $new_table = "_${table}_new";
my $schema = "pt_osc";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $master_dsn = $sb->dsn_for('master');
my $sample     = "t/pt-online-schema-change/samples";

sub start_and_kill_pt_osc {
    my $extra_args = shift;

    my ($pause_file_fh, $pause_file) = tempfile();
    my $args = "$master_dsn,D=$schema,t=$table --alter='DROP COLUMN d' --execute --pause-file=$pause_file $extra_args";

    my $pid = fork();
    if (!$pid) {
        open(STDERR, '>', $pause_file);
        open(STDOUT, '>', $pause_file);
        exec("$trunk/bin/pt-online-schema-change $args");
        exit(1);
    }

    # wait for pt-osc to start
    my $pt_osc_started = 0;
    for (1..60) {
        my $row = eval { $dbh->selectrow_arrayref("SHOW CREATE TABLE $schema.$new_table") };
        if (defined $row) {
            $pt_osc_started = 1;
            last;
        }

        sleep(1);
    }

    die "pt-osc didn't start on time" unless $pt_osc_started;
    kill('INT', $pid) or die "failed to send INT signal to pt-osc (pid: $pid)";
    waitpid($pid, 0);
    my $exit_code = $? >> 8;

    my $output = do {
        local $/ = undef;
        <$pause_file_fh>;
    };

    unlink($pause_file);
    close($pause_file_fh);

    return ($output, $exit_code);
}

# #############################################################################
# absent --preserve-table-after-interrupt --preserve-triggers-after-interrupt
# #############################################################################
{
    # Loads pt_osc.t with cols id (pk), c (unique index),, d.
    $sb->load_file('master', "$sample/basic_no_fks_innodb.sql");

    my ($output, $exit_code) = start_and_kill_pt_osc("");

    is(
        $exit_code,
        1,
        "absent preserve-table-after-interrupt preserve-triggers-after-interrupt: exit code == 1 due to SIGINT"
    );

    my $tables = $dbh->selectall_arrayref("SHOW TABLES FROM $schema");
    is_deeply(
       $tables,
       [ ['_t_new'], ['t'] ],
       "absent preserve-table-after-interrupt preserve-triggers-after-interrupt: tables"
    ) or diag(Dumper($tables), $output);

    my $triggers = eval { $dbh->selectall_arrayref("SHOW TRIGGERS FROM $schema LIKE '$table'") };
    is(
       @$triggers,
       3,
       "absent preserve-table-after-interrupt preserve-triggers-after-interrupt: triggers"
    ) or diag(Dumper($triggers), $output);
}

# #############################################################################
# --preserve-table-after-interrupt --preserve-triggers-after-interrupt
# #############################################################################
{
    # Loads pt_osc.t with cols id (pk), c (unique index),, d.
    $sb->load_file('master', "$sample/basic_no_fks_innodb.sql");

    my ($output, $exit_code) = start_and_kill_pt_osc("--preserve-new-table-after-interrupt --preserve-triggers-after-interrupt");

    is(
        $exit_code,
        1,
        "preserve-table-after-interrupt preserve-triggers-after-interrupt: exit code == 1 due to SIGINT"
    );

    my $tables = $dbh->selectall_arrayref("SHOW TABLES FROM $schema");
    is_deeply(
       $tables,
       [ ['_t_new'], ['t'] ],
       "preserve-table-after-interrupt preserve-triggers-after-interrupt: tables"
    ) or diag(Dumper($tables), $output);

    my $triggers = eval { $dbh->selectall_arrayref("SHOW TRIGGERS FROM $schema LIKE '$table'") };
    is(
       @$triggers,
       3,
       "preserve-table-after-interrupt preserve-triggers-after-interrupt: triggers"
    ) or diag(Dumper($triggers), $output);
}

# #############################################################################
# --no-preserve-table-after-interrupt --no-preserve-triggers-after-interrupt
# #############################################################################
{
    # Loads pt_osc.t with cols id (pk), c (unique index),, d.
    $sb->load_file('master', "$sample/basic_no_fks_innodb.sql");

    my ($output, $exit_code) = start_and_kill_pt_osc("--no-preserve-new-table-after-interrupt --no-preserve-triggers-after-interrupt");

    is(
        $exit_code,
        1,
        "no-preserve-table-after-interrupt no-preserve-triggers-after-interrupt: exit code == 1 due to SIGINT"
    );

    my $tables = $dbh->selectall_arrayref("SHOW TABLES FROM $schema");
    is_deeply(
       $tables,
       [ ['t'] ],
       "no-preserve-table-after-interrupt no-preserve-triggers-after-interrupt: tables"
    ) or diag(Dumper($tables), $output);

    my $triggers = eval { $dbh->selectall_arrayref("SHOW TRIGGERS FROM $schema LIKE '$table'") };
    is(
       @$triggers,
       0,
       "no-preserve-table-after-interrupt no-preserve-triggers-after-interrupt: triggers"
    ) or diag(Dumper($triggers), $output);
}

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
