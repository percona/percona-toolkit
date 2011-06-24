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

use MaatkitTest;
use Sandbox;
require "$trunk/bin/pt-upgrade";

# This runs immediately if the server is already running, else it starts it.
diag(`$trunk/sandbox/start-sandbox master 12347 >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');
my $dbh2 = $sb->get_dbh_for('slave2');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to second sandbox master';
}
else {
   plan tests => 5;
}

$sb->load_file('master', 't/pt-upgrade/samples/001/tables.sql');
$sb->load_file('slave2', 't/pt-upgrade/samples/001/tables.sql');

my $output;
my $cmd = "$trunk/bin/pt-upgrade h=127.1,P=12345,u=msandbox,p=msandbox P=12347 --compare results,warnings --zero-query-times --compare-results-method rows --limit 10";

# This test really deals with,
#   http://code.google.com/p/maatkit/issues/detail?id=754
#   http://bugs.mysql.com/bug.php?id=49634

$dbh2->do('set global query_cache_size=1000000');

my $qc = $dbh2->selectrow_arrayref('show variables like "query_cache_size"')->[1];
ok(
   $qc > 999000,
   'Query size'
);

$qc = $dbh2->selectrow_arrayref('show variables like "query_cache_type"')->[1];
is(
   $qc,
   'ON',
   'Query cache ON'
);


diag(`$cmd $trunk/t/pt-upgrade/samples/001/one-error.log >/dev/null 2>&1`);
$output = `$cmd $trunk/t/pt-upgrade/samples/001/one-error.log`;
like(
   $output,
   qr/# 3B323396273BC4C7-1 127.1:12347 Failed to execute query.+Unknown column 'borked' in 'field list' \[for Statement "select borked"\] at .+?\n\n/,
   '--clear-warnings',
);

# This produces a similar result to --clear-warnings.  The difference is that
# the script reports that the borked query has both Errors and Warnings.
# This happens because with --clear-warnings the script fails to clear the
# warnings for the borked query (since it has no tables) so it skips the
# CompareWarnings module (it skips any module that fails) thereby negating its
# ability to check/report Warnings.

# Normalize path- and script-dependent parts of the error message (like the
# line number at which the error occurs).
$output = `$cmd --no-clear-warnings $trunk/t/pt-upgrade/samples/001/one-error.log`;
like(
   $output,
   qr/# 3B323396273BC4C7-1 127.1:12347 Failed to execute query.+Unknown column 'borked' in 'field list' \[for Statement "select borked"\] at .+?\n\n/,
   '--no-clear-warnings'
);

$dbh2->do('set global query_cache_size=0');
$qc = $dbh2->selectrow_arrayref('show variables like "query_cache_size"')->[1];
ok(
   $qc == 0,
   'Query size'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
$sb->wipe_clean($dbh2);
exit;
