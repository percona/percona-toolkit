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
use Test::More tests => 7;

use PerconaTest;
use Sandbox;
use DSNParser;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

my $output;

my $pid_file = '/tmp/pt-query-digest.test.pid';
`rm $pid_file >/dev/null 2>&1`;

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch $pid_file`;
$output = `$trunk/bin/pt-query-digest $trunk/commont/t/samples/slow002.txt --pid $pid_file 2>&1`;
like(
   $output,
   qr{PID file $pid_file exists},
   'Dies if PID file exists (--pid without --daemonize) (issue 391)'
);
`rm $pid_file >/dev/null 2>&1`;

# #########################################################################
# Daemonizing and pid creation
# #########################################################################
SKIP: {
   skip "Cannot connect to sandbox master", 5 unless $dbh;

   my $cmd = "$trunk/bin/pt-query-digest --daemonize --pid $pid_file --processlist h=127.1,P=12345,u=msandbox,p=msandbox --log /dev/null";
   `$cmd`;
   $output = `ps xw | grep -v grep | grep '$cmd'`;
   like($output, qr/$cmd/, 'It is running');
   ok(-f $pid_file, 'PID file created');

   my ($pid) = $output =~ /^\s*(\d+)/;
   chomp($output = `cat $pid_file`);
   is($output, $pid, 'PID file has correct PID');

   kill 15, $pid;
   sleep 0.25;
   $output = `ps xw | grep -v grep | grep '$cmd'`;
   is($output, "", 'It is not running');
   ok(
      !-f $pid_file,
      'Removes its PID file'
   );
};

# #############################################################################
# Done.
# #############################################################################
`rm $pid_file >/dev/null 2>&1`;
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
