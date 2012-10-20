#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use RawLogParser;
use PerconaTest;

my $p = new RawLogParser();

my $oktorun = 1;
my $sample  = "t/lib/samples/rawlogs/";

test_log_parser(
   parser  => $p,
   file    => $sample.'rawlog001.txt',
   oktorun => sub { $oktorun = $_[0]; },
   result  => [
      {  pos_in_log => 0,
         arg        => 'SELECT c FROM t WHERE id=1',
         bytes      => 26,
         cmd        => 'Query',
         Query_time => 0,
      },
      {  pos_in_log => 27,
         arg        => '/* Hello, world! */ SELECT * FROM t2 LIMIT 1',
         bytes      => 44,
         cmd        => 'Query',
         Query_time => 0,
      }
   ]
);

is(
   $oktorun,
   0,
   'Sets oktorun'
);
$oktorun = 1;

# #############################################################################
# Done.
# #############################################################################
done_testing;
exit;
