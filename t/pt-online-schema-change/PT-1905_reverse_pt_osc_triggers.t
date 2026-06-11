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
use threads;
use Time::HiRes qw( usleep );
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

plan tests => 5;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

$sb->load_file('source', "t/pt-online-schema-change/samples/pt-153.sql");

sub start_thread {
   my ($dsn_opts) = @_;
   my $dp = new DSNParser(opts=>$dsn_opts);
   my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
   my $dbh = $sb->get_dbh_for('source');
   PTDEBUG && diag("Thread started...");

   local $SIG{KILL} = sub { 
       PTDEBUG && diag("Exit thread");
       threads->exit ;
   };

   for (my $i=0; $i < 1_000_000; $i++) {
       eval {
           $dbh->do("INSERT INTO test.t1 (f2,f4) VALUES (1,3)");
       };
   }
}

my $thr = threads->create('start_thread', $dsn_opts);
threads->yield();

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $output;
my $exit_status;

sleep(1); # Let is generate some rows. 

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args, "$source_dsn,D=test,t=t1",
         '--execute', 
         '--alter', "DROP COLUMN f3", 
         '--reverse-triggers', '--no-drop-old-table',
         ),
      },
);

is(
      $exit_status,
      0,
      "Exit status is 0",
) or diag($output);

like(
      $output,
      qr/Successfully altered `test`.`t1`/s,
      "Successfully altered `test`.`t1`",
);

my $triggers_sql = "SELECT TRIGGER_SCHEMA, TRIGGER_NAME, DEFINER, EVENT_OBJECT_SCHEMA, EVENT_OBJECT_TABLE, ACTION_STATEMENT, "
                 . "       EVENT_MANIPULATION, ACTION_TIMING "
                 . "  FROM INFORMATION_SCHEMA.TRIGGERS "
                 . " WHERE TRIGGER_SCHEMA = 'test' ORDER BY TRIGGER_NAME";

my $rows = $source_dbh->selectall_arrayref($triggers_sql, {Slice =>{}});

is_deeply (
    want_triggers(), 
    $rows,
    "Reverse triggers in place",
);

# Kill the thread otherwise the count will be different because we are running 2 separate queries.
$thr->kill('KILL'); 
$thr->join();

my $new_count = $source_dbh->selectrow_hashref('SELECT COUNT(*) AS cnt FROM test.t1');
my $old_count = $source_dbh->selectrow_hashref('SELECT COUNT(*) AS cnt FROM test._t1_old');

is (
    $old_count->{cnt},
    $new_count->{cnt}, 
    "Rows count is correct",
);

$source_dbh->do("DROP DATABASE IF EXISTS test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;


# Heres just to make the test more clear.
sub want_triggers {
    return [
        {
          action_statement => 'BEGIN DECLARE CONTINUE HANDLER FOR 1146 begin end; DELETE IGNORE FROM `test`.`_t1_old` WHERE `test`.`_t1_old`.`id` <=> OLD.`id`; END',
          action_timing => 'AFTER',
          definer => 'msandbox@%',
          event_manipulation => 'DELETE',
          event_object_schema => 'test',
          event_object_table => 't1',
          trigger_name => 'rt_pt_osc_test__t1_new_del',
          trigger_schema => 'test'
        },
        {
          action_statement => 'BEGIN DECLARE CONTINUE HANDLER FOR 1146 begin end; REPLACE INTO `test`.`_t1_old` (`id`, `f2`, `f4`) VALUES (NEW.`id`, NEW.`f2`, NEW.`f4`);END',
          action_timing => 'AFTER',
          definer => 'msandbox@%',
          event_manipulation => 'INSERT',
          event_object_schema => 'test',
          event_object_table => 't1',
          trigger_name => 'rt_pt_osc_test__t1_new_ins',
          trigger_schema => 'test'
        },
        {
          action_statement => 'BEGIN DECLARE CONTINUE HANDLER FOR 1146 begin end; DELETE IGNORE FROM `test`.`_t1_old` WHERE !(OLD.`id` <=> NEW.`id`) AND `test`.`_t1_old`.`id` <=> OLD.`id`; REPLACE INTO `test`.`_t1_old` (`id`, `f2`, `f4`) VALUES (NEW.`id`, NEW.`f2`, NEW.`f4`); END',
          action_timing => 'AFTER',
          definer => 'msandbox@%',
          event_manipulation => 'UPDATE',
          event_object_schema => 'test',
          event_object_table => 't1',
          trigger_name => 'rt_pt_osc_test__t1_new_upd',
          trigger_schema => 'test'
        },
    ];
}
