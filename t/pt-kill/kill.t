#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::HiRes qw(sleep);
use Test::More;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-kill";

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $output;
my $dsn = $sb->dsn_for('master');
my $cnf = '/tmp/12345/my.sandbox.cnf';

# TODO:  These tests need something to match, so we background
# a SLEEP(4) query and match that, but this isn't ideal because
# it's time-based.  Better is to use a specific db and --match-db.
my $sys_cmd = "/tmp/12345/use -e 'select sleep(4)' >/dev/null 2>&1 &";

# #############################################################################
# Test that --kill kills the connection.
# #############################################################################

system($sys_cmd);
sleep 0.5;
my $rows = $dbh->selectall_hashref('show processlist', 'id');
my $pid;
map  { $pid = $_->{id} }
grep { $_->{info} && $_->{info} =~ m/select sleep\(4\)/ }
values %$rows;

ok(
   $pid,
   'Got proc id of sleeping query'
) or diag(Dumper($rows));

$output = output(
   sub {
      pt_kill::main('-F', $cnf, qw(--kill --print --run-time 1 --interval 1),
         "--match-info", 'select sleep\(4\)')
   },
);

like(
   $output,
   qr/KILL $pid /,
   '--kill'
);

sleep 0.5;
$rows = $dbh->selectall_hashref('show processlist', 'id');

my $con_alive = grep { $_->{id} eq $pid } values %$rows;
ok(
   !$con_alive,
   'Killed connection'
);

# #############################################################################
# Test that --kill-query only kills the query, not the connection.
# #############################################################################

# Here's how this works.  This cmd is going to try 2 queries on the same
# connection: sleep5 and sleep3.  --kill-query will kill sleep5 causing
# sleep3 to start using the same connection id (pid).
system("/tmp/12345/use -e 'select sleep(5); select sleep(3)' >/dev/null&");
sleep 0.5;
$rows = $dbh->selectall_hashref('show processlist', 'id');
$pid = 0;  # reuse, reset
map  { $pid = $_->{id} }
grep { $_->{info} && $_->{info} =~ m/select sleep\(5\)/ }
values %$rows;

ok(
   $pid,
   'Got proc id of sleeping query'
);

$output = output(
   sub { pt_kill::main('-F', $cnf, qw(--kill-query --print --run-time 1 --interval 1),
      '--match-info', 'select sleep\(5\)') },
);
like(
   $output,
   qr/KILL QUERY $pid /,
   '--kill-query'
);

sleep 1;
$rows = $dbh->selectall_hashref('show processlist', 'id');
$con_alive = grep { $_->{id} eq $pid } values %$rows;
ok(
   $con_alive,
   'Killed query, not connection'
);

is(
   ($rows->{$pid}->{info} || ''),
   'select sleep(3)',
   'Connection is still alive'
);

# #############################################################################
# Test that --log-dsn
# #############################################################################

$dbh->do("DROP DATABASE IF EXISTS `kill_test`");
$dbh->do("CREATE DATABASE `kill_test`");

my $sql = OptionParser->read_para_after(
   "$trunk/bin/pt-kill", qr/MAGIC_create_log_table/);
$sql =~ s/kill_log/`kill_test`.`log_table`/;

my $log_dsn = "h=127.1,P=12345,u=msandbox,p=msandbox,D=kill_test,t=log_table";

$dbh->do($sql);

{
   system($sys_cmd);
   sleep 0.5;

   local $EVAL_ERROR;
   eval {
      pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1),
         "--match-info", 'select sleep\(4\)',
         "--log-dsn", $log_dsn,
      )
   };

   is(
      $EVAL_ERROR,
      '',
      "--log-dsn works if the table exists and --create-log-table wasn't passed in."
   );

   local $EVAL_ERROR;
   my $results = eval { $dbh->selectall_arrayref("SELECT * FROM `kill_test`.`log_table`", { Slice => {} } ) };

   is(
       $EVAL_ERROR,
       '',
      "...and we can query the table"
   ) or diag $EVAL_ERROR;

   is(
      scalar @$results,
      1,
      "...which contains one entry"
   );

   my $reason = $dbh->selectrow_array("SELECT reason FROM `kill_test`.`log_table` WHERE kill_id=1");

   is(
      $reason,
      'Query matches Info spec',
      'reason gets set to something sensible'
   );

   TODO: {
      local $TODO = "Time_ms currently isn't reported";
      my $time_ms = $dbh->selectrow_array("SELECT Time_ms FROM `kill_test`.`log_table` WHERE kill_id=1");
      ok(
         $time_ms,
         "TIME_MS"
      );
   }

   my $result = shift @$results;

   # This returns a string ala 2012-12-04T17:47:52
   my $current_ts = Transformers::ts(time());
   # Use whatever format MySQL is using
   ($current_ts)  = $dbh->selectrow_array(qq{SELECT TIMESTAMP('$current_ts')});

   # Chop off the minutes & seconds. If the rest of the date is right,
   # this is unlikely to be broken.
   substr($current_ts, -5, 5, "");
   like(
      $result->{timestamp},
      qr/\A\Q$current_ts\E.{5}\Z/,
      "Bug 1086259: pt-kill in non-daemon mode logs timestamps incorrectly"
   );
   
   my $against = {
      user    => 'msandbox',
      host    => 'localhost',
      db      => undef,
      command => 'Query',
      state   => ($sandbox_version lt '5.1' ? "executing" : "User sleep"),
      info    => 'select sleep(4)',
   };
   my %trimmed_result;
   @trimmed_result{ keys %$against } = @{$result}{ keys %$against };
   $trimmed_result{host} =~ s/localhost:[0-9]+/localhost/;

   is_deeply(
      \%trimmed_result,
      $against,
      "...and was populated as expected",
   ) or diag(Dumper($result));
   
   system($sys_cmd);
   sleep 0.5;

   local $EVAL_ERROR;
   eval {
      pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1),
         "--create-log-table",
         "--match-info", 'select sleep\(4\)',
         "--log-dsn", $log_dsn,
      )
   };

   is(
      $EVAL_ERROR,
      '',
      "--log-dsn --create-log-table and the table exists"
   );
}

{
   $dbh->do("DROP TABLE IF EXISTS `kill_test`.`log_table`");

   system($sys_cmd);
   sleep 0.5;

   local $EVAL_ERROR;
   eval {
      pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1),
         "--create-log-table",
         "--match-info", 'select sleep\(4\)',
         "--log-dsn", $log_dsn,
      )
   };

   is(
      $EVAL_ERROR,
      '',
      "--log-dsn --create-log-table and the table doesn't exists"
   );
}

{
   $dbh->do("DROP TABLE IF EXISTS `kill_test`.`log_table`");

   local $EVAL_ERROR;
   eval {
      pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1),
         "--match-info", 'select sleep\(4\)',
         "--log-dsn", $log_dsn,
      )
   };

   like(
      $EVAL_ERROR,
      qr/\Q--log-dsn table does not exist. Please create it or specify\E/,
      "By default, --log-dsn doesn't autogenerate a table"
   );
}

for my $dsn (
   q/h=127.1,P=12345,u=msandbox,p=msandbox,t=log_table/,
   q/h=127.1,P=12345,u=msandbox,p=msandbox,D=kill_test/,
   q/h=127.1,P=12345,u=msandbox,p=msandbox/,
) {
   local $EVAL_ERROR;
   eval {
      pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1),
         "--match-info", 'select sleep\(4\)',
         "--log-dsn", $dsn,
      )
   };

   like(
      $EVAL_ERROR,
      qr/\Q--log-dsn does not specify a database (D) or a database-qualified table (t)\E/,
      "--log-dsn croaks if t= or D= are absent"
   );
}

# Run it twice
for (1,2) {
   system($sys_cmd);
   sleep 0.5;

   pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1),
      "--create-log-table",
      "--match-info", 'select sleep\(4\)',
      "--log-dsn", $log_dsn,
   );
}

my $results = $dbh->selectall_arrayref("SELECT * FROM `kill_test`.`log_table`");

is(
   scalar @$results,
   2,
   "Different --log-dsn runs reuse the same table."
);


# --log-dsn and --daemonize

$dbh->do("DELETE FROM kill_test.log_table");
$sb->wait_for_slaves();

my $pid_file = "/tmp/pt-kill-test.$PID";
my $log_file = "/tmp/pt-kill-test-log.$PID";
diag(`rm -f $pid_file $log_file >/dev/null 2>&1`);

my $slave2_dbh = $sb->get_dbh_for('slave2');
my $slave2_dsn = $sb->dsn_for('slave2');

system($sys_cmd);
sleep 0.5;

system("$trunk/bin/pt-kill $dsn --daemonize --run-time 1 --kill-query --interval 1 --match-info 'select sleep' --log-dsn $slave2_dsn,D=kill_test,t=log_table --pid $pid_file --log $log_file");
PerconaTest::wait_for_files($pid_file);         # start
# ...                                           # run
PerconaTest::wait_until(sub { !-f $pid_file});  # stop

$results = $slave2_dbh->selectall_arrayref("SELECT * FROM kill_test.log_table");

ok(
   scalar @$results,
   "--log-dsn --daemonize (bug 1209436)"
) or diag(Dumper($results));

$dbh->do("DROP DATABASE IF EXISTS kill_test");

PerconaTest::wait_until(
   sub {
      $results = $dbh->selectall_hashref('SHOW PROCESSLIST', 'id');
      return !grep { ($_->{info} || '') =~ m/sleep \(4\)/ } values %$results;
   }
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
