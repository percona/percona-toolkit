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
require VersionParser;

use Data::Dumper;

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $replica_dbh  = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica';
}

my @args   = qw(--set-vars innodb_lock_wait_timeout=3);
my $output = "";
my $dsn    = "h=127.1,P=12345,u=msandbox,p=msandbox";
my $exit   = 0;
my $sample = "t/pt-online-schema-change/samples";

$sb->load_file('source', "$sample/basic_no_fks_innodb.sql");

# #############################################################################
# --where does not run without --no-drop-new-table and --no-swap-tables
# unless option --force also specified
# #############################################################################

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
      '--alter', 'drop column id', '--where', 'id > 10', '--execute') }
);

like(
   $output,
   qr/Using option --where together with --drop-new-table and --swap-tables may lead to data loss, therefore this operation is only allowed if option --force also specified. Aborting./i,
   'Did not run with --where and without --no-drop-new-table, --no-swap-tables and --force'
) or diag($output);

is(
   $exit,
   17,
   'Exit code 17 (UNSUPPORTED_OPERATION) with --where and without --no-drop-new-table, --no-swap-tables and --force'
);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
      '--alter', 'drop column id', '--where', 'id > 10', '--execute',
      '--no-drop-new-table') }
);

like(
   $output,
   qr/Using option --where together with --drop-new-table and --swap-tables may lead to data loss, therefore this operation is only allowed if option --force also specified. Aborting./i,
   'Did not run with --where and without --no-swap-tables and --force'
) or diag($output);

is(
   $exit,
   17,
   'Exit code 17 (UNSUPPORTED_OPERATION) with --where and without --no-swap-tables and --force'
);

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
      '--alter', 'drop column id', '--where', 'id > 10', '--execute',
      '--no-swap-tables') }
);

like(
   $output,
   qr/Using option --where together with --drop-new-table and --swap-tables may lead to data loss, therefore this operation is only allowed if option --force also specified. Aborting./i,
   'Did not run with --where and without --no-drop-new-table and --force'
) or diag($output);

is(
   $exit,
   17,
   'Exit code 17 (UNSUPPORTED_OPERATION) with --where and without --no-drop-new-table and --force'
);

# #############################################################################
# Multiple situations when option --where works
# #############################################################################

$output = output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
      '--alter', 'add column e int', '--where', 'id > 10', '--execute',
      '--no-swap-tables', '--no-drop-new-table', 
      '--new-table-name', 't_pt_1751') }
);

like(
   $output,
   qr/Successfully altered/i,
   'Option --where runs with --no-drop-new-table and --no-swap-tables'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.t_pt_1751"`;
is(
   $output + 0,
   10,
   'Only 10 rows copied'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.t_pt_1751 where id <= 10"`;
is(
   $output + 0,
   0,
   'Rows, satisfying --where condition are not copied'
) or diag($output);

$sb->load_file('source', "$sample/basic_no_fks_innodb.sql");

$output = output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
      '--alter', 'add column e int', '--where', 'id > 10', '--execute',
      '--force') }
);

like(
   $output,
   qr/Successfully altered/i,
   'Option --where runs with --force'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.t"`;
is(
   $output + 0,
   10,
   'Only 10 rows copied'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.t where id <= 10"`;
is(
   $output + 0,
   0,
   'Rows, satisfying --where condition are not copied'
) or diag($output);

# Same test with chunk size = 1

$sb->load_file('source', "$sample/basic_no_fks_innodb.sql");

$output = output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
      '--alter', 'add column e int', '--where', 'id > 10', '--execute',
      '--no-swap-tables', '--no-drop-new-table', '--chunk-size', '1',
      '--new-table-name', 't_pt_1751') }
);

like(
   $output,
   qr/Successfully altered/i,
   'Option --where runs with --no-drop-new-table and --no-swap-tables'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.t_pt_1751"`;
is(
   $output + 0,
   10,
   'Only 10 rows copied'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.t_pt_1751 where id <= 10"`;
is(
   $output + 0,
   0,
   'Rows, satisfying --where condition are not copied'
) or diag($output);

$sb->load_file('source', "$sample/basic_no_fks_innodb.sql");

$output = output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=t",
      '--alter', 'add column e int', '--where', 'id > 10', '--execute',
      '--force', '--chunk-size', '1',) }
);

like(
   $output,
   qr/Successfully altered/i,
   'Option --where runs with --force'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.t"`;
is(
   $output + 0,
   10,
   'Only 10 rows copied'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.t where id <= 10"`;
is(
   $output + 0,
   0,
   'Rows, satisfying --where condition are not copied'
) or diag($output);


# #############################################################################
# Option --where and foreign keys
# #############################################################################

$sb->load_file('source', "$sample/basic_with_fks.sql");

$output = output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=city",
      '--alter', 'drop column last_update', '--where', 'city_id >= 3', '--execute',
      '--alter-foreign-keys-method', 'rebuild_constraints', '--force') }
);

like(
   $output,
   qr/Successfully altered/i,
   'Option --where runs with --force and --alter-foreign-keys-method=rebuild_constraints'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.city"`;
is(
   $output + 0,
   3,
   'Only 3 rows copied'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.city where city_id < 3"`;
is(
   $output + 0,
   0,
   'Rows, satisfying --where condition are not copied'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.country"`;
is(
   $output + 0,
   5,
   'Table country not corrupted'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.address"`;
is(
   $output + 0,
   5,
   'Table address not modified'
) or diag($output);

$sb->load_file('source', "$sample/basic_with_fks.sql");

$output = output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=city",
      '--alter', 'drop column last_update', '--where', 'city_id >= 3', '--execute',
      '--alter-foreign-keys-method', 'auto', '--force') }
);

like(
   $output,
   qr/Successfully altered/i,
   'Option --where runs with --force and --alter-foreign-keys-method=auto'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.city"`;
is(
   $output + 0,
   3,
   'Only 3 rows copied'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.city where city_id < 3"`;
is(
   $output + 0,
   0,
   'Rows, satisfying --where condition are not copied'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.country"`;
is(
   $output + 0,
   5,
   'Table country not corrupted'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.address"`;
is(
   $output + 0,
   5,
   'Table address not modified'
) or diag($output);

$sb->load_file('source', "$sample/basic_with_fks.sql");

$output = output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=city",
      '--alter', 'drop column last_update', '--where', 'city_id >= 3', '--execute',
      '--alter-foreign-keys-method', 'drop_swap', '--force') }
);

like(
   $output,
   qr/Successfully altered/i,
   'Option --where runs with --force and --alter-foreign-keys-method=drop_swap'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.city"`;
is(
   $output + 0,
   3,
   'Only 3 rows copied'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.city where city_id < 3"`;
is(
   $output + 0,
   0,
   'Rows, satisfying --where condition are not copied'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.country"`;
is(
   $output + 0,
   5,
   'Table country not corrupted'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.address"`;
is(
   $output + 0,
   5,
   'Table address not modified'
) or diag($output);

$sb->load_file('source', "$sample/basic_with_fks.sql");

$output = output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=city",
      '--alter', 'drop column last_update', '--where', 'city_id >= 3', '--execute',
      '--alter-foreign-keys-method', 'none', '--force') }
);

like(
   $output,
   qr/Successfully altered/i,
   'Option --where runs with --force and --alter-foreign-keys-method=none'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.city"`;
is(
   $output + 0,
   3,
   'Only 3 rows copied'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.city where city_id < 3"`;
is(
   $output + 0,
   0,
   'Rows, satisfying --where condition are not copied'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.country"`;
is(
   $output + 0,
   5,
   'Table country not corrupted'
) or diag($output);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.address"`;
is(
   $output + 0,
   5,
   'Table address not modified'
) or diag($output);

$sb->load_file('source', "$sample/basic_with_fks.sql");

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=city",
      '--alter', 'drop column last_update', '--where', 'city_id >= 3', '--execute',
      '--alter-foreign-keys-method', 'rebuild_constraints', 
      '--no-drop-new-table', '--no-swap-tables') }
);

like(
   $output,
   qr/Child tables found and option --where specified. Rebuilding foreign key constraints may lead to errors./i,
   'Option --where does not run without --force and --alter-foreign-keys-method=rebuild_constraints when child tables are found'
) or diag($output);

is(
   $exit,
   1,
   'Exit code 1 with --where and child tables'
);

$output = `/tmp/12345/use -N -e "select count(*) from pt_osc.address"`;
is(
   $output + 0,
   5,
   'Table address not modified'
) or diag($output);

$sb->load_file('source', "$sample/basic_with_fks.sql");

($output, $exit) = full_output(
   sub { pt_online_schema_change::main(@args, "$dsn,D=pt_osc,t=city",
      '--alter', 'drop column last_update', '--where', 'city_id >= 3', '--execute',
      '--alter-foreign-keys-method', 'auto',
      '--no-drop-new-table', '--no-swap-tables') }
);

like(
   $output,
   qr/Child tables found and option --where specified. Rebuilding foreign key constraints may lead to errors./i,
   'Option --where does not run without --force and --alter-foreign-keys-method=auto when child tables are found'
) or diag($output);

is(
   $exit,
   1,
   'Exit code 1 with --where and child tables'
);

# #############################################################################
# Done.
# #############################################################################

$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
#
done_testing;
