#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.  See http://code.google.
com/p/maatkit/wiki/Testing"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";

};

use strict;
use warnings FATAL => 'all';
use English qw( -no_match_vars );
use Test::More;
use Data::Dumper;

use PerconaTest; 
use Sandbox;
require "$trunk/bin/pt-slave-delay";

my $dp  = DSNParser->new(opts => $dsn_opts);
my $sb  = Sandbox->new(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $dbh        = $sb->get_dbh_for('slave1');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to MySQL slave.';
}
elsif ( !@{$dbh->selectcol_arrayref("SHOW DATABASES LIKE 'sakila'")} ) {
   plan skip_all => 'sakila db not loaded';
}

my $cnf = '/tmp/12346/my.sandbox.cnf';
my $output;

# #############################################################################
# Issue 991: Make mk-slave-delay reconnect to db when it loses the dbconnection
# #############################################################################

# Fork a child that will stop the slave while we, the parent, run
# tool.  The tool should report that it lost its slave cxn, then
# the child should restart the slave, and the tool should report
# that it reconnected and did some work, ending with "Setting slave
# to run normally".
my $pid = fork();
if ( $pid ) {
   # parent
   $output = output(
      sub { pt_slave_delay::main('-F', $cnf, qw(--interval 1 --run-time 4)) },
      stderr => 1,
   );
   like(
      $output,
      qr/Lost connection.+?Setting slave to run/ms,
      "Reconnect to slave"
   );
}
else {
   # child
   sleep 1;
   diag(`/tmp/12346/stop >/dev/null`);
   sleep 1;
   diag(`/tmp/12346/start >/dev/null`);
   # Ensure we don't break the sandbox -- instance 12347 will be disconnected
   # when its master gets rebooted
   diag(`/tmp/12347/use -e "stop slave; start slave"`);
   exit;
}
# Reap the child.
waitpid ($pid, 0);

$sb->wait_for_slaves;

# Do it all over again, but this time KILL instead of restart.
$pid = fork();
if ( $pid ) {
   # parent. Note the --database mysql
   $output = output(
      sub { pt_slave_delay::main('-F', $cnf, qw(--interval 1 --run-time 4),
         qw(--database mysql)) },
      stderr => 1,
   );
   like(
      $output,
      qr/Lost connection.+?Setting slave to run/ms,
      "Reconnect to slave when KILL'ed"
   );
}
else {
   # child. Note that we'll kill the parent's 'mysql' connection
   sleep 1;
   my $c_dbh = $sb->get_dbh_for('slave1');
   my @cxn = @{$c_dbh->selectall_arrayref('show processlist', {Slice => {}})};
   foreach my $c ( @cxn ) {
      # The parent's connection:
      # {command => 'Sleep',db => 'mysql',host => 'localhost',id => '5',info => undef,state => '',time => '1',user => 'msandbox'}
      if ( ($c->{db} || '') eq 'mysql' && ($c->{user} || '') eq 'msandbox'
         && ($c->{command} || '') ne 'Binlog Dump' # Don't kill the slave threads from 12347 or others!
      ) {
         diag("Killing connection on slave1: $c->{id} ($c->{command})");
         $c_dbh->do("KILL $c->{id}");
      }
   }
   exit;
}
# Reap the child.
waitpid ($pid, 0);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
