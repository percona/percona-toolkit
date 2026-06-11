#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 6;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-kill";
require VersionParser;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';
my $cmd = "$trunk/bin/pt-kill -F $cnf -h 127.1";

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

`$cmd --print --interval 1s --run-time 20 --pid /tmp/pt-kill.pid --log /tmp/pt-kill.log --daemonize --busy-time 5  --kill-query --victims all --charset utf8mb4`;
$output = `ps -eaf | grep 'pt-kill \-F'`;

ok(
   -f '/tmp/pt-kill.pid',
   'PID file created'
);

ok(
   -f '/tmp/pt-kill.log',
   'Log file created'
);

$source_dbh->do("select '柏木', sleep(20);");

wait_until(sub { return !-f '/tmp/pt-kill.pid' });
ok(
   !-f '/tmp/pt-kill.pid',
   'PID file removed'
);

$output = `cat /tmp/pt-kill.log`;

unlike(
   $output,
   qr/Wide character in printf/,
   'Error "Wide character in printf" not printed'
) or diag($output);

like(
   $output,
   qr/柏木/,
   'Hieroglif printed'
) or diag($output);

diag(`rm -rf /tmp/pt-kill.log 2>/dev/null`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh) if $source_dbh;
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
