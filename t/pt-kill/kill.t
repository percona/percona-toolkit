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
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
