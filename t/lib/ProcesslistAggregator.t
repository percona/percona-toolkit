#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 7;

use ProcesslistAggregator;
use TextResultSetParser;
use DSNParser;
use MySQLDump;
use Quoter;
use TableParser;
use MaatkitTest;

my $r   = new TextResultSetParser();
my $apl = new ProcesslistAggregator();

isa_ok($apl, 'ProcesslistAggregator');

sub test_aggregate {
   my ($file, $expected, $msg) = @_;
   my $proclist = $r->parse( load_file($file) );
   is_deeply(
      $apl->aggregate($proclist),
      $expected,
      $msg
   );
   return;
}

test_aggregate(
   't/lib/samples/pl/recset001.txt',
   {
      command => { query     => { time => 0, count => 1 } },
      db      => { ''        => { time => 0, count => 1 } },
      user    => { msandbox  => { time => 0, count => 1 } },
      state   => { ''        => { time => 0, count => 1 } },
      host    => { localhost => { time => 0, count => 1 } },
   },
   'Aggregate basic processlist'
);

test_aggregate(
   't/lib/samples/pl/recset004.txt',
   {
      db => {
         NULL   => { count => 1,  time => 0 },
         forest => { count => 50, time => 533 }
      },
      user => {
         user1 => { count => 50, time => 533 },
         root  => { count => 1,  time => 0 }
      },
      host => {
         '0.1.2.11' => { count => 21, time => 187 },
         '0.1.2.12' => { count => 25, time => 331 },
         '0.1.2.21' => { count => 4,  time => 15 },
         localhost  => { count => 1,  time => 0 }
      },
      state => {
         locked    => { count => 24, time => 84 },
         preparing => { count => 26, time => 449 },
         null      => { count => 1,  time => 0 }
      },
      command => { query => { count => 51, time => 533 } }
   },
   'Sample with 51 processes',
);

my $aggregate = $apl->aggregate($r->parse(load_file('t/lib/samples/pl/recset003.txt')));
cmp_ok(
   $aggregate->{db}->{NULL}->{count},
   '==',
   3,
   '113 proc sample: 3 NULL db'
);
cmp_ok(
   $aggregate->{db}->{happy}->{count},
   '==',
   110,
   '113 proc sample: 110 happy db'
);

# #############################################################################
# Issue 777: ProcesslistAggregator undef bug
# #############################################################################
$r = new TextResultSetParser(
   value_for => {
      '' => undef,
   }
);

my $row = $r->parse(load_file('t/lib/samples/pl/recset007.txt'));

is_deeply(
   $row,
   [
      {
         Command => undef,
         Host => undef,
         Id => '9',
         Info => undef,
         State => undef,
         Time => undef,
         User => undef,
         db => undef
      }
   ],
   'Pathological undef row'
);

is_deeply(
   $apl->aggregate($row),
   {
      command => {
       null => {
         count => 1,
         time => 0
       }
      },
      db => {
       NULL => {
         count => 1,
         time => 0
       }
      },
      host => {
       NULL => {
         count => 1,
         time => 0
       }
      },
      state => {
       null => {
         count => 1,
         time => 0
       }
      },
      user => {
       NULL => {
         count => 1,
         time => 0
       }
      },
   },
   'Pathological undef row aggregate'
);

exit;
