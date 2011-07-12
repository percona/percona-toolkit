#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 13;

use TextResultSetParser;
use PerconaTest;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $r = new TextResultSetParser();
isa_ok($r, 'TextResultSetParser');

throws_ok(
   sub { $r->parse(load_file('t/lib/samples/slowlogs/slow002.txt')) },
   qr/Cannot determine if text is/,
   "Dies if output type cannot be determined"
);

is_deeply(
   $r->parse( load_file('t/lib/samples/pl/recset001.txt') ),
   [
      {
         Time     => '0',
         Command  => 'Query',
         db       => '',
         Id       => '9',
         Info     => 'show processlist',
         User     => 'msandbox',
         State    => '',
         Host     => 'localhost'
      },
   ],
   'Basic tablular processlist'
);

is_deeply(
   $r->parse( load_file('t/lib/samples/pl/recset002.txt') ),
   [
      {
         Time     => '4',
         Command  => 'Query',
         db       => 'foo',
         Id       => '1',
         Info     => 'select * from foo1;',
         User     => 'user1',
         State    => 'Locked',
         Host     => '1.2.3.4:3333'
      },
      {
         Time     => '5',
         Command  => 'Query',
         db       => 'foo',
         Id       => '2',
         Info     => 'select * from foo2;',
         User     => 'user1',
         State    => 'Locked',
         Host     => '1.2.3.4:5455'
      },
   ],
   '2 row vertical processlist'
);

my $recset = $r->parse ( load_file('t/lib/samples/pl/recset003.txt') );
cmp_ok(
   scalar @$recset,
   '==',
   113,
   '113 row vertical processlist'
);

$recset = $r->parse( load_file('t/lib/samples/pl/recset004.txt') );
cmp_ok(
   scalar @$recset,
   '==',
   51,
   '51 row vertical processlist'
);

is_deeply(
   $r->parse( load_file('t/lib/samples/pl/recset005.txt') ),
   [
      {
         Id    => '29392005',
         User  => 'remote',
         Host  => '1.2.3.148:49718',
         db    => 'happy',
         Command => 'Sleep',
         Time  => '17',
         State => undef,
         Info  => undef,
      }
   ],
   '1 vertical row, No State value'
);

is_deeply(
   $r->parse( load_file('t/lib/samples/pl/recset009.txt') ),
   [
      {
         Id      => '21',
         User    => 'msandbox',
         Host    => 'localhost:54732',
         db      => undef,
         Command => 'Binlog Dump',
         Time    => '3081',
         State   => 'Has sent all binlog to slave; waiting for binlog to be updated',
         Info    => undef,
      },
      {
         Id      => '41',
         User    => 'msandbox',
         Host    => 'localhost',
         db      => undef,
         Command => 'Query',
         Time    => '0',
         State   => undef,
         Info    => 'show full processlist',
      }
   ],
   'Horizontal, tab-separated'
);

$recset = $r->parse(load_file('t/lib/samples/show-variables/vars001.txt'));
# Should only get the var once.
my $got_var = grep { $_->{Variable_name} eq 'warning_count' } @$recset;
is(
   $got_var,
   1,
   "vars001.txt"
);

$recset = $r->parse(load_file('t/lib/samples/show-variables/vars002.txt'));
$got_var = grep { $_->{Variable_name} eq 'warning_count' } @$recset;
is(
   $got_var,
   1,
   "vars002.txt"
);


# #############################################################################
# Parse with NAME_lc for lowercase key/col names.
# #############################################################################
$r = new TextResultSetParser(NAME_lc => 1);

$recset = $r->parse(load_file('t/lib/samples/show-variables/vars001.txt'));
$got_var = grep { $_->{variable_name} eq 'warning_count' } @$recset;
is(
   $got_var,
   1,
   "NAME_lc tabular"
);

$recset = $r->parse(load_file('t/lib/samples/show-variables/vars002.txt'));
$got_var = grep { $_->{variable_name} eq 'warning_count' } @$recset;
is(
   $got_var,
   1,
   "NAME_lc tab-separated"
);

is_deeply(
   $r->parse( load_file('t/lib/samples/pl/recset002.txt') ),
   [
      {
         time     => '4',
         command  => 'Query',
         db       => 'foo',
         id       => '1',
         info     => 'select * from foo1;',
         user     => 'user1',
         state    => 'Locked',
         host     => '1.2.3.4:3333'
      },
      {
         time     => '5',
         command  => 'Query',
         db       => 'foo',
         id       => '2',
         info     => 'select * from foo2;',
         user     => 'user1',
         state    => 'Locked',
         host     => '1.2.3.4:5455'
      },
   ],
   "NAME_lc vertical"
);

# #############################################################################
# Done.
# #############################################################################
exit;
