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
use File::Path qw(make_path remove_tree);

if ($sandbox_version lt '8.0') {
   plan skip_all => 'This test needs MySQL 8.0+';
}

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $source3_port   = 2900;
my $source_basedir = "/tmp/$source3_port";
my $source3_cnf    = "$source_basedir/my.sandbox.cnf";

my $new_dir_a      = '/tmp/pt-osc-data-dir-a';
my $new_dir_b      = '/tmp/pt-osc-data-dir-b';
my $unknown_dir    = '/tmp/pt-osc-data-dir-unknown';
my $home_test_dir  = '/tmp/pt-osc-innodb-home-test';

my $extra_defaults_file = '/tmp/pt-data-dir-my.sandbox.cnf';

my $dbh3;
my $dsn3;

sub _reload_source3 {
   $dbh3 = $sb->get_dbh_for('source3');
   $dsn3 = $sb->dsn_for('source3');
}

sub _rewrite_source3_config {
   my (%opts) = @_;

   open my $in, '<', $source3_cnf or die "Cannot read $source3_cnf: $OS_ERROR";
   my @lines = <$in>;
   close $in;

   @lines = grep { $_ !~ /^\s*(?:innodb_directories)\s*=/ } @lines;

   if ( defined $opts{innodb_directories} ) {
      push @lines, "innodb_directories='" . $opts{innodb_directories} . "'\n";
   }

   open my $out, '>', $source3_cnf or die "Cannot write $source3_cnf: $OS_ERROR";
   print {$out} @lines;
   close $out;
}

sub _restart_source3 {
   diag(`$source_basedir/stop >/dev/null`);
   diag(`$source_basedir/start >/dev/null`);
   #diag(`cat /tmp/$source3_port/data/mysqld.log`);
   _reload_source3();
}

sub _run_pt_osc_with_data_dir {
   my ($dir) = @_;

   my @args = (qw(--set-vars innodb_lock_wait_timeout=3));
   my ($output, $exit_status) = full_output(
      sub {
         pt_online_schema_change::main(
            @args,
            "$dsn3,D=test,t=t3",
            '--execute',
            '--alter', 'engine=innodb',
            '--data-dir', $dir,
         );
      },
      stderr => 1,
   );

   return ($output, $exit_status);
}

sub _reload_test_table {
   $sb->load_file('source3', 't/pt-online-schema-change/samples/pt-244.sql');
   $dbh3->do('FLUSH TABLES');
}

remove_tree($new_dir_a, $new_dir_b, $unknown_dir, $home_test_dir);
make_path($new_dir_a, $new_dir_b, $unknown_dir, $home_test_dir);

diag(`echo "[mysqld]\ninnodb_data_home_dir=$home_test_dir/" > /tmp/pt-data-dir-my.sandbox.cnf`);

local $ENV{EXTRA_DEFAULTS_FILE} = $extra_defaults_file;
diag(`$trunk/sandbox/stop-sandbox $source3_port >/dev/null`);
diag(`$trunk/sandbox/start-sandbox source $source3_port >/dev/null`);

_reload_source3();

if ( !$dbh3 ) {
   plan skip_all => 'Cannot connect to sandbox source'  ;
}

my ($datadir, $innodb_data_home_dir) =
   $dbh3->selectrow_array('SELECT @@datadir, @@innodb_data_home_dir');

# Case 1: allowed directory from multi-value innodb_directories.

_rewrite_source3_config(
   innodb_directories => "$new_dir_a;$new_dir_b",
);

_restart_source3();
_reload_test_table();

my ($output, $exit_status) = _run_pt_osc_with_data_dir($new_dir_b);

is(
   $exit_status,
   0,
   'data-dir works when directory is in multi-value innodb_directories'
) or diag($output);

like(
   $output,
   qr/Successfully altered/s,
   'Got success message for allowed directory',
) or diag($output);

# Case 2: not allowed directory should fail.

_reload_test_table();
($output, $exit_status) = _run_pt_osc_with_data_dir($unknown_dir);

isnt(
   $exit_status,
   0,
   'data-dir fails when directory is unknown to InnoDB',
) or diag($output);

like(
   $output,
   qr/Data directory \Q$unknown_dir\E is not known to InnoDB/s,
   'Got expected error for unknown directory',
) or diag($output);

# Case 3: no innodb_directories, data-dir in @@innodb_data_home_dir (if set).

_reload_test_table();
($output, $exit_status) = _run_pt_osc_with_data_dir($innodb_data_home_dir);
is(
    $exit_status,
    0,
    'data-dir works when using @@innodb_data_home_dir',
) or diag($output);

like(
    $output,
    qr/Successfully altered/s,
    'Got success message for @@innodb_data_home_dir',
) or diag($output);

# Case 4: innodb_data_home_dir-only setup and known/unknown checks.
# We set innodb_data_home_dir without setting innodb_directories, then
# validate one known and one unknown directory.

_rewrite_source3_config();
_restart_source3();

_reload_test_table();
($output, $exit_status) = _run_pt_osc_with_data_dir($home_test_dir);

is(
   $exit_status,
   0,
   'data-dir works when directory is known via innodb_data_home_dir and innodb_directories is unset',
) or diag($output);

like(
   $output,
   qr/Successfully altered/s,
   'Got success message for innodb_data_home_dir-only setup',
) or diag($output);

_reload_test_table();
my $home_unknown_dir = '/tmp/pt-osc-innodb-home-unknown';
make_path($home_unknown_dir);
($output, $exit_status) = _run_pt_osc_with_data_dir($home_unknown_dir);

isnt(
   $exit_status,
   0,
   'data-dir fails when directory is unknown in innodb_data_home_dir-only setup',
) or diag($output);

like(
   $output,
   qr/Data directory \Q$home_unknown_dir\E is not known to InnoDB/s,
   'Got expected unknown-directory error in innodb_data_home_dir-only setup',
) or diag($output);

$dbh3->do('DROP DATABASE IF EXISTS test');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh3);
diag(`$trunk/sandbox/stop-sandbox $source3_port >/dev/null`);
diag(`rm -rf $new_dir_a $new_dir_b $unknown_dir $home_test_dir $extra_defaults_file`);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
