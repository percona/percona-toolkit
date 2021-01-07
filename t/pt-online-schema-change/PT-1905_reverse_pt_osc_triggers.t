#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use threads;

use English qw(-no_match_vars);
use Test::More;

use Data::Dumper;
use PerconaTest;
use Sandbox;
use SqlModes;
use File::Temp qw/ tempdir /;

plan tests => 4;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $master_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;

$sb->load_file('master', "t/pt-online-schema-change/samples/pt-153.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$master_dsn,D=test,t=t1",
         '--execute', 
         '--alter', "DROP COLUMN f3", 
         '--reverse-triggers', '--no-drop-old-table',
         ),
      },
);

diag($output);

is(
      $exit_status,
      0,
      "PT-200 Adding a column named unique_xxx is not detected as an unique index",
);

like(
      $output,
      qr/Successfully altered `test`.`t1`/s,
      "PT-200 Adding field having 'unique' in the name",
);

   my $triggers_sql = "SELECT TRIGGER_SCHEMA, TRIGGER_NAME, DEFINER, ACTION_STATEMENT, SQL_MODE, "
                    . "       CHARACTER_SET_CLIENT, COLLATION_CONNECTION, EVENT_MANIPULATION, ACTION_TIMING "
                    . "  FROM INFORMATION_SCHEMA.TRIGGERS "
                    . " WHERE TRIGGER_SCHEMA = 'test'" ;
my $want = [
  {
    action_statement => 'REPLACE INTO `test`.`_t1_old` (`id`, `f2`, `f4`) VALUES (NEW.`id`, NEW.`f2`, NEW.`f4`)',
    action_timing => 'AFTER',
    character_set_client => 'latin1',
    collation_connection => 'latin1_swedish_ci',
    definer => 'msandbox@%',
    event_manipulation => 'INSERT',
    sql_mode => 'ONLY_FULL_GROUP_BY,NO_AUTO_VALUE_ON_ZERO,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION',
    trigger_name => 'pt_osc_test_t1_ins',
    trigger_schema => 'test'
  },
  {
    action_statement => 'BEGIN DELETE IGNORE FROM `test`.`_t1_old` WHERE !(OLD.`id` <=> NEW.`id`) AND `test`.`_t1_old`.`id` <=> OLD.`id`;REPLACE INTO `test`.`_t1_old` (`id`, `f2`, `f4`) VALUES (NEW.`id`, NEW.`f2`, NEW.`f4`);END',
    action_timing => 'AFTER',
    character_set_client => 'latin1',
    collation_connection => 'latin1_swedish_ci',
    definer => 'msandbox@%',
    event_manipulation => 'UPDATE',
    sql_mode => 'ONLY_FULL_GROUP_BY,NO_AUTO_VALUE_ON_ZERO,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION',
    trigger_name => 'pt_osc_test_t1_upd',
    trigger_schema => 'test'
  },
  {
    action_statement => 'DELETE IGNORE FROM `test`.`_t1_old` WHERE `test`.`_t1_old`.`id` <=> OLD.`id`',
    action_timing => 'AFTER',
    character_set_client => 'latin1',
    collation_connection => 'latin1_swedish_ci',
    definer => 'msandbox@%',
    event_manipulation => 'DELETE',
    sql_mode => 'ONLY_FULL_GROUP_BY,NO_AUTO_VALUE_ON_ZERO,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION',
    trigger_name => 'pt_osc_test_t1_del',
    trigger_schema => 'test'
  }
];

my $rows = $master_dbh->selectall_arrayref($triggers_sql, {Slice =>{}});
is (
    @$want, 
    @$rows,
    "Reverse triggers in place",
);
$master_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
