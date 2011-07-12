#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 3;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-kill";

my $qr = new QueryRewriter();

my $proclist = 
   [  {  'Time'    => '488',
         'Command' => 'Connect',
         'db'      => undef,
         'Id'      => '4',
         'Info'    => undef,
         'User'    => 'system user',
         'State'   => 'Waiting for master to send event',
         'Host'    => ''
      },
      {  'Time'    => '488',
         'Command' => 'Connect',
         'db'      => undef,
         'Id'      => '5',
         'Info'    => undef,
         'User'    => 'system user',
         'State' =>
            'Has read all relay log; waiting for the slave I/O thread to update it',
         'Host' => ''
      },
      {  'Time'    => '416',
         'Command' => 'Sleep',
         'db'      => undef,
         'Id'      => '7',
         'Info'    => undef,
         'User'    => 'msandbox',
         'State'   => '',
         'Host'    => 'localhost'
      },
      {  'Time'    => '0',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '8',
         'Info'    => 'show full processlist',
         'User'    => 'msandbox',
         'State'   => undef,
         'Host'    => 'localhost:41655'
      },
      {  'Time'    => '467',
         'Command' => 'Binlog Dump',
         'db'      => undef,
         'Id'      => '2',
         'Info'    => undef,
         'User'    => 'msandbox',
         'State' =>
            'Has sent all binlog to slave; waiting for binlog to be updated',
         'Host' => 'localhost:56246'
      },
      {  'Time'    => '91',
         'Command' => 'Sleep',
         'db'      => undef,
         'Id'      => '40',
         'Info'    => undef,
         'User'    => 'msandbox',
         'State'   => '',
         'Host'    => 'localhost'
      },
      {  'Time'    => '91',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '41',
         'Info'    => 'optimize table foo',
         'User'    => 'msandbox',
         'State'   => 'Query',
         'Host'    => 'localhost'
      },
      {  'Time'    => '91',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '42',
         'Info'    => 'select * from foo',
         'User'    => 'msandbox',
         'State'   => 'Locked',
         'Host'    => 'localhost'
      },
      {  'Time'    => '91',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '43',
         'Info'    => 'select * from foo',
         'User'    => 'msandbox',
         'State'   => 'executing',
         'Host'    => 'localhost'
      },
   ];

my $classes = pt_kill::group_queries(
   proclist      => $proclist,
   group_by      => 'Info',
   QueryRewriter => $qr,
);

is_deeply(
   $classes,
   {
      'NULL' => [
         {  'Time'    => '488',
            'Command' => 'Connect',
            'db'      => undef,
            'Id'      => '4',
            'Info'    => undef,
            'User'    => 'system user',
            'State'   => 'Waiting for master to send event',
            'Host'    => ''
         },
         {  'Time'    => '488',
            'Command' => 'Connect',
            'db'      => undef,
            'Id'      => '5',
            'Info'    => undef,
            'User'    => 'system user',
            'State' =>
               'Has read all relay log; waiting for the slave I/O thread to update it',
            'Host' => ''
         },
         {  'Time'    => '416',
            'Command' => 'Sleep',
            'db'      => undef,
            'Id'      => '7',
            'Info'    => undef,
            'User'    => 'msandbox',
            'State'   => '',
            'Host'    => 'localhost'
         },
         {  'Time'    => '467',
            'Command' => 'Binlog Dump',
            'db'      => undef,
            'Id'      => '2',
            'Info'    => undef,
            'User'    => 'msandbox',
            'State' =>
               'Has sent all binlog to slave; waiting for binlog to be updated',
            'Host' => 'localhost:56246'
         },
         {  'Time'    => '91',
            'Command' => 'Sleep',
            'db'      => undef,
            'Id'      => '40',
            'Info'    => undef,
            'User'    => 'msandbox',
            'State'   => '',
            'Host'    => 'localhost'
         },
      ],
      'show full processlist' => [
         {  'Time'    => '0',
            'Command' => 'Query',
            'db'      => undef,
            'Id'      => '8',
            'Info'    => 'show full processlist',
            'User'    => 'msandbox',
            'State'   => undef,
            'Host'    => 'localhost:41655'
         },
      ],
      'optimize table foo' => [
         {  'Time'    => '91',
            'Command' => 'Query',
            'db'      => undef,
            'Id'      => '41',
            'Info'    => 'optimize table foo',
            'User'    => 'msandbox',
            'State'   => 'Query',
            'Host'    => 'localhost'
         },
      ],
      'select * from foo' => [
         {  'Time'    => '91',
            'Command' => 'Query',
            'db'      => undef,
            'Id'      => '42',
            'Info'    => 'select * from foo',
            'User'    => 'msandbox',
            'State'   => 'Locked',
            'Host'    => 'localhost'
         },
         {  'Time'    => '91',
            'Command' => 'Query',
            'db'      => undef,
            'Id'      => '43',
            'Info'    => 'select * from foo',
            'User'    => 'msandbox',
            'State'   => 'executing',
            'Host'    => 'localhost'
         },
      ],
   },
   "Group by Info"
);

$proclist = [
      {  'Time'    => '91',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '42',
         'Info'    => 'select * from foo where id=1',
         'User'    => 'msandbox',
         'State'   => 'Locked',
         'Host'    => 'localhost'
      },
      {  'Time'    => '92',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '42',
         'Info'    => 'select * from foo where id=1',
         'User'    => 'msandbox',
         'State'   => 'Locked',
         'Host'    => 'localhost'
      },
      {  'Time'    => '93',
         'Command' => 'Query',
         'db'      => undef,
         'Id'      => '42',
         'Info'    => 'select * from foo where id=3',
         'User'    => 'msandbox',
         'State'   => 'Locked',
         'Host'    => 'localhost'
      },
   ];

$classes = pt_kill::group_queries(
   proclist      => $proclist,
   group_by      => 'Info',
   QueryRewriter => $qr,
);

is_deeply(
   $classes,
   {
      'select * from foo where id=1' => [
         {  'Time'    => '91',
            'Command' => 'Query',
            'db'      => undef,
            'Id'      => '42',
            'Info'    => 'select * from foo where id=1',
            'User'    => 'msandbox',
            'State'   => 'Locked',
            'Host'    => 'localhost'
         },
         {  'Time'    => '92',
            'Command' => 'Query',
            'db'      => undef,
            'Id'      => '42',
            'Info'    => 'select * from foo where id=1',
            'User'    => 'msandbox',
            'State'   => 'Locked',
            'Host'    => 'localhost'
         },
      ],
      'select * from foo where id=3' => [
         {  'Time'    => '93',
            'Command' => 'Query',
            'db'      => undef,
            'Id'      => '42',
            'Info'    => 'select * from foo where id=3',
            'User'    => 'msandbox',
            'State'   => 'Locked',
            'Host'    => 'localhost'
         },
      ],
   },
   "Group by Info with similar fingerprints"
);

$classes = pt_kill::group_queries(
   proclist      => $proclist,
   group_by      => 'fingerprint',
   QueryRewriter => $qr,
);

is_deeply(
   $classes,
   {
      'select * from foo where id=?' => [
         {  'Time'    => '91',
            'Command' => 'Query',
            'db'      => undef,
            'Id'      => '42',
            'Info'    => 'select * from foo where id=1',
            'User'    => 'msandbox',
            'State'   => 'Locked',
            'Host'    => 'localhost'
         },
         {  'Time'    => '92',
            'Command' => 'Query',
            'db'      => undef,
            'Id'      => '42',
            'Info'    => 'select * from foo where id=1',
            'User'    => 'msandbox',
            'State'   => 'Locked',
            'Host'    => 'localhost'
         },
         {  'Time'    => '93',
            'Command' => 'Query',
            'db'      => undef,
            'Id'      => '42',
            'Info'    => 'select * from foo where id=3',
            'User'    => 'msandbox',
            'State'   => 'Locked',
            'Host'    => 'localhost'
         },
      ],
   },
   "Group by fingerprint"
);

# #############################################################################
# Done.
# #############################################################################
exit;
