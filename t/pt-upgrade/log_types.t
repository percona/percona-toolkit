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
use File::Basename;
use File::Temp qw(tempdir);

$ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} = 1; 
$ENV{PRETTY_RESULTS} = 1; 

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-upgrade";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('host1');

# Just testing that the other log types work, so we don't need
# the second host.  By "other" I mean gen, bin, tcpdump, and raw
# because other tests make extensive use of slow logs.

# DO NOT test the results here.  That's better done in compare_hosts.t
# or compare_results.t by creating a numbered dir (e.g. 005/) with
# sample log and output files.

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox host1'; 
}

my $host1_dsn   = $sb->dsn_for('host1');
my $tmpdir      = tempdir("/tmp/pt-upgrade.$PID.XXXXXX", CLEANUP => 1);
my $samples     = "$trunk/t/pt-upgrade/samples";
my $lib_samples = "$trunk/t/lib/samples";
my $exit_status = 0;
my $output;

# #############################################################################
# genlog
# #############################################################################

$output = output(
   sub {
      $exit_status = pt_upgrade::main($host1_dsn, '--save-results', $tmpdir,
         qw(--type genlog),
         "$samples/genlog001.txt",
   )},
   stderr => 1,
);

is(
   $exit_status,
   0,
   "genlog001: exit 0"
);

# There are 7 events, but only 1 SELECT query.  The INSERT query
# should be filtered out by default.
like(
   $output,
   qr/queries_written\s+1/,
   "genlog001: wrote 1 query"
);

# #############################################################################
# binlog
# #############################################################################

$output = output(
   sub {
      $exit_status = pt_upgrade::main($host1_dsn, '--save-results', $tmpdir,
         qw(--type binlog),
         "$lib_samples/binlogs/binlog001.txt",
   )},
   stderr => 1,
);

is(
   $exit_status,
   0,
   "binlog001: exit 0 (read-only)"
);

# There are 7 events, but only 1 SELECT query.  The INSERT query
# should be filtered out by default.
like(
   $output,
   qr/queries_written\s+0/,
   "binlog001: no queries (read-only)"
);

$output = output(
   sub {
      $exit_status = pt_upgrade::main($host1_dsn, '--save-results', $tmpdir,
         qw(--type binlog --no-read-only),
         "$lib_samples/binlogs/binlog001.txt",
   )},
   stderr => 1,
);

is(
   $exit_status,
   0,
   "binlog001: exit 0"
);

# There are 7 events, but only 1 SELECT query.  The INSERT query
# should be filtered out by default.
like(
   $output,
   qr/queries_written\s+10/,
   "binlog001: wrote 10 queries"
);

# #############################################################################
# tcpdump
# #############################################################################

$output = output(
   sub {
      $exit_status = pt_upgrade::main($host1_dsn, '--save-results', $tmpdir,
         qw(--type tcpdump),
         "$lib_samples/tcpdump/tcpdump002.txt",
   )},
   stderr => 1,
);

is(
   $exit_status,
   0,
   "tcpdump001: exit 0",
);

like(
   $output,
   qr/queries_written\s+2/,
   "tcpdump002: wrote 2 queries"
);

# #############################################################################
# rawlog
# #############################################################################

$output = output(
   sub {
      $exit_status = pt_upgrade::main($host1_dsn, '--save-results', $tmpdir,
         qw(--type rawlog),
         "$lib_samples/rawlogs/rawlog002.txt",
   )},
   stderr => 1,
);

is(
   $exit_status,
   0,
   "rawlog001: exit 0",
);

like(
   $output,
   qr/queries_written\s+2/,
   "rawlog002: wrote 2 queries"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
