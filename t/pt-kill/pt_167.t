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
use threads;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-kill";

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $o = new OptionParser(description => 'Diskstats',
   file        => "$trunk/bin/pt-kill",
);
$o->get_specs("$trunk/bin/pt-kill");
$o->get_opts();

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

sub start_thread {
   my ($dp, $o, $dsn, $sleep_time) = @_;

   diag("Thread started");

   my $cxn = new Cxn(DSNParser => $dp, OptionParser => $o, dsn => $dsn);
   $cxn->connect();
   my $dbh = $cxn->dbh();
   sleep(2);
   diag("Running 'SELECT SLEEP(10)' in thread #1");
   my $sth = $dbh->prepare('SELECT SLEEP(10)');
   # Since this query is going to be killed, wrap the execution in an eval to prevent
   # displaying the error message.
   eval {
       $sth->execute();
   };
   diag("Exit from thread #1");
}


sub start_thread_2 {
   my ($dp, $o, $dsn, $sleep_time) = @_;

   diag("Thread 2 started");

   my $cxn = new Cxn(DSNParser => $dp, OptionParser => $o, dsn => $dsn);
   $cxn->connect();
   my $dbh = $cxn->dbh();
   for (my $i=0; $i < 30; $i++) {
       my $query = "SELECT $i";
       diag("Running '$query' in thread #2");
       my $sth = $dbh->prepare($query);
       select (undef, undef, undef, 1);
   }
   diag("Exit from thread #2");
}

my $dsn = "h=127.1,P=12345,u=msandbox,p=msandbox,D=sakila;mysql_server_prepare=1";
my $thr1 = threads->create('start_thread', $dp, $o, $dp->parse($dsn), 1);
my $thr2= threads->create('start_thread_2', $dp, $o, $dp->parse($dsn), 1);
threads->yield();

sleep(4);

my $rows = $dbh->selectall_hashref('show processlist', 'id');
my $pid = 0;  # reuse, reset
map  { $pid = $_->{id} }
grep { $_->{info} && $_->{info} =~ m/SELECT SLEEP\(10\)/ }
values %$rows;

ok(
   $pid,
   "Got proc id of sleeping query: $pid"
);

$dsn = $sb->dsn_for('master');
my $output = output(
   sub { pt_kill::main($dsn, "--kill-busy-commands","Query,Execute", qw(--run-time 30s --interval 1 --kill --busy-time 2s --print --match-info), "^(select|SELECT)"), },
   stderr => 1,
);

diag("====================================================================================================");
diag($output);
diag("====================================================================================================");

like(
   $output,
   qr/KILL $pid \(Execute/,
   '--kill-query'
) or diag($output);

$thr1->join();
$thr2->join();


# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
