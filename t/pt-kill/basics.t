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
require "$trunk/bin/pt-kill";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 5;
}

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-kill -F $cnf -h 127.1";

# Shell out to a sleep(10) query and try to capture the query.
# Backticks don't work here.
system("/tmp/12345/use -h127.1 -P12345 -umsandbox -pmsandbox -e 'select sleep(5)' >/dev/null &");

$output = `$cmd --busy-time 1s --print --run-time 10`;

# $output ought to be something like
# 2009-05-27T22:19:40 KILL 5 (Query 1 sec) select sleep(10)
# 2009-05-27T22:19:41 KILL 5 (Query 2 sec) select sleep(10)
# 2009-05-27T22:19:42 KILL 5 (Query 3 sec) select sleep(10)
# 2009-05-27T22:19:43 KILL 5 (Query 4 sec) select sleep(10)
# 2009-05-27T22:19:44 KILL 5 (Query 5 sec) select sleep(10)
# 2009-05-27T22:19:45 KILL 5 (Query 6 sec) select sleep(10)
# 2009-05-27T22:19:46 KILL 5 (Query 7 sec) select sleep(10)
# 2009-05-27T22:19:47 KILL 5 (Query 8 sec) select sleep(10)
# 2009-05-27T22:19:48 KILL 5 (Query 9 sec) select sleep(10)
my @times = $output =~ m/\(Query (\d+) sec\)/g;
ok(
   @times > 2 && @times < 7,
   "There were 2 to 5 captures"
) or print STDERR Dumper($output);

# This is to catch a bad bug where there wasn't any sleep time when
# --iterations  was 0, and another bug when --run-time was not respected.
# Do it all over again, this time with --iterations 0.
# Re issue 1181, --iterations no longer exists, but we'll still keep this test.
system("/tmp/12345/use -h127.1 -P12345 -umsandbox -pmsandbox -e 'select sleep(10)' >/dev/null&");
$output = `$cmd --busy-time 1s --print --run-time 11s`;
@times = $output =~ m/\(Query (\d+) sec\)/g;
ok(
   @times > 7 && @times < 12,
   'Approximately 9 or 10 captures with --iterations 0'
) or print STDERR Dumper($output);


# ############################################################################
# --verbose
# ############################################################################
$output = output(
   sub { pt_kill::main('-F', $cnf, qw(--run-time 2s --busy-time 1 --print),
      qw(--verbose)) },
);
like(
   $output,
   qr/Checking processlist/,
   '--verbose'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
