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
else {
   plan tests => 20;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';

# #############################################################################
# Test that --kill kills the connection.
# #############################################################################

# Shell out to a sleep(10) query and try to capture the query.
# Backticks don't work here.
system("/tmp/12345/use -h127.1 -P12345 -umsandbox -pmsandbox -e 'select sleep(4)' >/dev/null&");
sleep 0.5;
my $rows = $dbh->selectall_hashref('show processlist', 'id');
my $pid;
map  { $pid = $_->{id} }
grep { $_->{info} && $_->{info} =~ m/select sleep\(4\)/ }
values %$rows;

ok(
   $pid,
   'Got proc id of sleeping query'
);

$output = output(
   sub { pt_kill::main('-F', $cnf, qw(--kill --print --run-time 1 --interval 1),
            "--match-info", 'select sleep\(4\)',
         )
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
system("/tmp/12345/use -h127.1 -P12345 -umsandbox -pmsandbox -e 'select sleep(5); select sleep(3)' >/dev/null&");
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

$dbh->do($sql);

{
   system("/tmp/12345/use -h127.1 -P12345 -umsandbox -pmsandbox -e 'select sleep(4)' >/dev/null&");
   sleep 0.5;
   local $@;
   eval {
      pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1),
         "--match-info", 'select sleep\(4\)',
         "--log-dsn", q!h=127.1,P=12345,u=msandbox,p=msandbox,d=kill_test,t=log_table!,
      )
   };
   ok !$@, "--log-dsn works if the table exists and --create-log-table wasn't passed in."
      or diag $@;

   local $@;
   my $results = eval { $dbh->selectall_arrayref("SELECT * FROM `kill_test`.`log_table`") };
   ok !$@, "...and we can query the table"
      or diag $@;

   is @{$results}, 1, "...which contains one entry";
   use Data::Dumper;
   my $reason = $dbh->selectrow_array("SELECT reason FROM `kill_test`.`log_table` WHERE kill_id=1");
   is $reason,
      'Query matches Info spec',
      'reason gets set to something sensible';

   TODO: {
      local $::TODO = "Time_ms currently isn't reported";
      my $time_ms = $dbh->selectrow_array("SELECT Time_ms FROM `kill_test`.`log_table` WHERE kill_id=1");
      ok $time_ms;
   }

   my $result = shift @$results;
   $result->[6] =~ s/localhost:[0-9]+/localhost/;
   is_deeply(
      [ @{$result}[5..8, 10, 11] ],
      [ 'msandbox', 'localhost', undef, 'Query', 'User sleep', 'select sleep(4)', ],
      "...and was populated as expected",
   );
   
   system("/tmp/12345/use -h127.1 -P12345 -umsandbox -pmsandbox -e 'select sleep(4)' >/dev/null&");
   sleep 0.5;
   local $@;
   eval {
      pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1 --create-log-table),
         "--match-info", 'select sleep\(4\)',
         "--log-dsn", q!h=127.1,P=12345,u=msandbox,p=msandbox,d=kill_test,t=log_table!,
      )
   };
   ok !$@, "--log-dsn works if the table exists and --create-log-table was passed in.";
}

{
   $dbh->do("DROP TABLE `kill_test`.`log_table`");

   system("/tmp/12345/use -h127.1 -P12345 -umsandbox -pmsandbox -e 'select sleep(4)' >/dev/null&");
   sleep 0.5;
   local $@;
   eval {
      pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1 --create-log-table),
         "--match-info", 'select sleep\(4\)',
         "--log-dsn", q!h=127.1,P=12345,u=msandbox,p=msandbox,d=kill_test,t=log_table!,
      )
   };
   ok !$@, "--log-dsn works if the table doesn't exists and --create-log-table was passed in.";
}

{
   $dbh->do("DROP TABLE `kill_test`.`log_table`");

   local $@;
   eval {
      pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1),
         "--match-info", 'select sleep\(4\)',
         "--log-dsn", q!h=127.1,P=12345,u=msandbox,p=msandbox,d=kill_test,t=log_table!,
      )
   };
   like $@,
      qr/\QTable 'kill_test.log_table' doesn't exist\E/,       #'
      "By default, --log-dsn doesn't autogenerate a table";
}

for my $dsn (
   q!h=127.1,P=12345,u=msandbox,p=msandbox,t=log_table!,
   q!h=127.1,P=12345,u=msandbox,p=msandbox,d=kill_test!,
   q!h=127.1,P=12345,u=msandbox,p=msandbox!,
) {
   local $@;
   eval {
      pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1),
         "--match-info", 'select sleep\(4\)',
         "--log-dsn", $dsn,
      )
   };
   like $@,
      qr/\QThe DSN passed in for --log-dsn must have a database and table set\E/,
      "--log-dsn croaks if t= or d= are absent";
}

# Run it twice
for (1,2) {
   system("/tmp/12345/use -h127.1 -P12345 -umsandbox -pmsandbox -e 'select sleep(4)' >/dev/null&");
   sleep 0.5;
   pt_kill::main('-F', $cnf, qw(--kill --run-time 1 --interval 1 --create-log-table),
      "--match-info", 'select sleep\(4\)',
      "--log-dsn", q!h=127.1,P=12345,u=msandbox,p=msandbox,d=kill_test,t=log_table!,
   );
}

my $results = $dbh->selectall_arrayref("SELECT * FROM `kill_test`.`log_table`");

is @{$results}, 2, "Different --log-dsn runs reuse the same table.";

$dbh->do("DROP DATABASE kill_test");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
