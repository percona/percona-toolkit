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

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-log-player";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 19;
}

my $output;
my $tmpdir = '/tmp/mk-log-player';
my $cmd = "$trunk/bin/pt-log-player --play $tmpdir -F /tmp/12345/my.sandbox.cnf h=127.1 --no-results";

diag(`rm -rf $tmpdir 2>/dev/null; mkdir $tmpdir`);

# #############################################################################
# Test that all session files gets assigned.
# #############################################################################
my @args = (qw(--dry-run --play), "$trunk/t/pt-log-player/samples/16sessions");
for my $n ( 1..16 ) {
   ok(
      no_diff(
         sub { pt_log_player::main(@args, '--threads', $n) },
         "t/pt-log-player/samples/assigned16.txt",
         sed  => [
            "'s!$trunk/t/pt-log-player/samples/16sessions/!!g'",
            "'s/Process [0-9]* plays //g'",
         ],
         sort => '',
      ),
      "Assigned 16 sessions to $n threads"
   );
}

# #############################################################################
# Test session playing.
# #############################################################################

$sb->load_file('master', 't/pt-log-player/samples/log.sql');
`$trunk/bin/pt-log-player --base-dir $tmpdir --session-files 2 --split Thread_id $trunk/t/pt-log-player/samples/log001.txt`;
`$cmd`;
is_deeply(
   $dbh->selectall_arrayref('select * from mk_log_player_1.tbl1 where a = 100 OR a = 555;'),
   [[100], [555]],
   '--play made table changes',
);

$sb->load_file('master', 't/pt-log-player/samples/log.sql');

`$cmd --only-select`;
is_deeply(
   $dbh->selectall_arrayref('select * from mk_log_player_1.tbl1 where a = 100 OR a = 555;'),
   [],
   'No table changes with --only-select',
);

# #############################################################################
# Issue 418: mk-log-player dies trying to play statements with blank lines
# #############################################################################
diag(`rm -rf $tmpdir 2>/dev/null; mkdir $tmpdir`);
`$trunk/bin/pt-log-player --split Thread_id --base-dir $tmpdir $trunk/t/lib/samples/slowlogs/slow020.txt`;

ok(
   no_diff(
      "$cmd --threads 1 --print",
      "t/pt-log-player/samples/play_slow020.txt",
   ),
   'Play session from log with blank lines in queries (issue 418)' 
);

diag(`rm session-results-*.txt 2>/dev/null`);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -rf $tmpdir 2>/dev/null`);
$sb->wipe_clean($dbh);
exit;
