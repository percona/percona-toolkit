#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";

   # The timestamps for unix_timestamp are East Coast (EST), so GMT-4.
   $ENV{TZ}='EST5EDT';
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 3;

use SimpleTCPDumpParser;
use PerconaTest;

my $in = "t/lib/samples/simple-tcpdump/"; 

my $p = new SimpleTCPDumpParser(watch => ':3306');

# Check that I can parse a log in the default format.
test_log_parser(
   parser => $p,
   file   => "$in/simpletcp001.txt",
   result => [
      {  ts         => '1301957863.804195',
         ts0        => '1301957863.804195',
         id         => 0,
         end        => '1301957863.804465',
         end1       => '1301957863.804473',
         arg        => undef,
         host       => '10.10.18.253',
         port       => '58297',
         pos_in_log => 0,
      },
      {  ts         => '1301957863.805481',
         ts0        => '1301957863.805481',
         id         => 1,
         end        => '1301957863.806026',
         end1       => '1301957863.806032',
         arg        => undef,
         host       => '10.10.18.253',
         port       => 40135,
         pos_in_log => 231,
      },
      {  ts         => '1301957863.805801',
         ts0        => '1301957863.805801',
         id         => 2,
         end        => '1301957863.806003',
         end1       => '1301957863.806003',
         arg        => undef,
         host       => '10.10.18.253',
         port       => 52726,
         pos_in_log => 308,
      },
   ],
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $p->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
