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

use Data::Dumper;
use PerconaTest;
use Sandbox;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $sample     = "t/pt-online-schema-change/samples/";
my $plugin     = "$trunk/$sample/plugins";
my $output;
my $exit_status;

# ############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1171653
# 
# ############################################################################
$sb->load_file('source', "$sample/basic_no_fks.sql");

# Should be greater than chunk-size and big enough, so plugin will trigger few times
my $num_rows = 5000;
diag("Loading $num_rows into the table. This might take some time.");
diag(`util/mysql_random_data_load --host=127.0.0.1 --port=12345 --user=msandbox --password=msandbox pt_osc t $num_rows`);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=pt_osc,t=t",
      "--alter", "CHARACTER SET utf9",
      '--plugin', "$plugin/before_die.pm",
      '--execute') },
);

like(
   $output,
   qr/PLUGIN before_die/s,
   'Plugin before_die called for invalid ALTER command'
);

like(
   $output,
   qr/Exit status: .*Unknown character set: 'utf9'/s,
   'Expected exit status for invalid ALTER command'
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=pt_osc,t=t",
      "--alter", "ENGINE=InnoDB",
      '--plugin', "$plugin/before_die_after_nibble.pm",
      '--execute') },
);

like(
   $output,
   qr/PLUGIN before_die/s,
   'Plugin before_die called for error while copying nibble'
);

like(
   $output,
   qr/Exit status: .*You have an error in your SQL syntax/s,
   'Expected exit status for error while copying nibble'
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=pt_osc,t=t",
      "--alter", "ENGINE=InnoDB",
      '--plugin', "$plugin/before_die_after_create.pm",
      '--execute') },
);

like(
   $output,
   qr/PLUGIN before_die/s,
   'Plugin before_die called for _die call'
);

like(
   $output,
   qr/Exit status: 4/s,
   'Expected exit status for table definition error handled in the _die call'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
