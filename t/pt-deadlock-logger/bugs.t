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
require "$trunk/bin/pt-deadlock-logger";

use Data::Dumper;

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/903443
# pt-deadlock-logger crashes on MySQL 5.5
# #############################################################################

my $innodb_status_sample = load_file("t/pt-deadlock-logger/samples/bug_903443.txt");

is_deeply(
   pt_deadlock_logger::parse_deadlocks($innodb_status_sample),
   {
      '1' => {
          db => 'test',
          hostname => 'localhost',
          id => 1,
          idx => 'PRIMARY',
          ip => '',
          lock_mode => 'X',
          lock_type => 'RECORD',
          query => 'update a set movie_id=96 where id =2',
          server => '',
          tbl => 'a',
          thread => '19',
          ts => '2011-12-12T22:52:42',
          txn_id => 0,
          txn_time => '161',
          user => 'root',
          victim => 0,
          wait_hold => 'w'
      },
      '2' => {
          db => 'test',
          hostname => 'localhost',
          id => 2,
          idx => 'PRIMARY',
          ip => '',
          lock_mode => 'X',
          lock_type => 'RECORD',
          query => 'update a set movie_id=98 where id =4',
          server => '',
          tbl => 'a',
          thread => '18',
          ts => '2011-12-12T22:52:42',
          txn_id => 0,
          txn_time => '1026',
          user => 'root',
          victim => 1,
          wait_hold => 'w'
      }
   },
   "Bug 903443: pt-deadlock-logger parses the thread id incorrectly for MySQL 5.5",
);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1082104
# pt-deadlock-logger problem when the user have a dash in the name
# #############################################################################

$innodb_status_sample = load_file("t/pt-deadlock-logger/samples/bug_1082104.txt");

is_deeply(
   pt_deadlock_logger::parse_deadlocks($innodb_status_sample),
   {
      '1' => {
          db => 'test',
          hostname => 'localhost',
          id => 1,
          idx => 'PRIMARY',
          ip => '',
          lock_mode => 'X',
          lock_type => 'RECORD',
          query => 'update a set movie_id=96 where id =2',
          server => '',
          tbl => 'a',
          thread => '19',
          ts => '2011-12-12T22:52:42',
          txn_id => 0,
          txn_time => '161',
          user => 'ro-ot',
          victim => 0,
          wait_hold => 'w'
      },
      '2' => {
          db => 'test',
          hostname => 'localhost',
          id => 2,
          idx => 'PRIMARY',
          ip => '',
          lock_mode => 'X',
          lock_type => 'RECORD',
          query => 'update a set movie_id=98 where id =4',
          server => '',
          tbl => 'a',
          thread => '18',
          ts => '2011-12-12T22:52:42',
          txn_id => 0,
          txn_time => '1026',
          user => 'ro-ot',
          victim => 1,
          wait_hold => 'w'
      }
   },
   "Bug 1082104: pt-deadlock-logger shows host as user when the username has a dash in the name",
);

# #############################################################################
# https://bugs.launchpad.net/percona-toolkit/+bug/1195034
# pt-deadlock-logger error: Use of uninitialized value $ts in pattern match
# #############################################################################

$innodb_status_sample = load_file("t/pt-deadlock-logger/samples/bug_1195034.txt");
my $deadlocks = pt_deadlock_logger::parse_deadlocks($innodb_status_sample);

is_deeply(
   $deadlocks,
   {
   },
   "Bug 1195034: TOO DEEP OR LONG SEARCH IN THE LOCK TABLE WAITS-FOR GRAPH"
) or diag(Dumper($deadlocks));

# #############################################################################
# Done.
# #############################################################################
done_testing;
exit;
