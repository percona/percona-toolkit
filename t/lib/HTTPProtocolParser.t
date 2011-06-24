#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 16;

use TcpdumpParser;
use ProtocolParser;
use HTTPProtocolParser;
use MaatkitTest;

my $tcpdump  = new TcpdumpParser();
my $protocol; # Create a new HTTPProtocolParser for each test.

# GET a very simple page.
$protocol = new HTTPProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/http/http_tcpdump001.txt',
   result   => [
      { ts              => '2009-11-09 11:31:52.341907',
        bytes           => '715',
        host            => '10.112.2.144',
        pos_in_log      => 0,
        Virtual_host    => 'hackmysql.com',
        arg             => 'get hackmysql.com/contact',
        Status_code     => '200',
        Query_time      => '0.651419',
        Transmit_time   => '0.000000',
      },
   ],
);

# Get http://www.percona.com/about-us.html
$protocol = new HTTPProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/http/http_tcpdump002.txt',
   result   => [
      {
         ts             => '2009-11-09 15:31:09.074855',
         Query_time     => '0.070097',
         Status_code    => '200',
         Transmit_time  => '0.000720',
         Virtual_host   => 'www.percona.com',
         arg            => 'get www.percona.com/about-us.html',
         bytes          => 3832,
         host           => '10.112.2.144',
         pos_in_log     => 206,
      },
      {
         ts             => '2009-11-09 15:31:09.157215',
         Query_time     => '0.068558',
         Status_code    => '200',
         Transmit_time  => '0.066490',
         Virtual_host   => 'www.percona.com',
         arg            => 'get www.percona.com/js/jquery.js',
         bytes          => 9921,
         host           => '10.112.2.144',
         pos_in_log     => 16362,
      },
      {
         ts             => '2009-11-09 15:31:09.346763',
         Query_time     => '0.066506',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'www.percona.com',
         arg            => 'get www.percona.com/images/menu_team.gif',
         bytes          => 344,
         host           => '10.112.2.144',
         pos_in_log     => 53100,
      },
      {
         ts             => '2009-11-09 15:31:09.373800',
         Query_time     => '0.045442',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'www.google-analytics.com',
         arg            => 'get www.google-analytics.com/__utm.gif?utmwv=1.3&utmn=1710381507&utmcs=UTF-8&utmsr=1280x800&utmsc=24-bit&utmul=en-us&utmje=1&utmfl=10.0%20r22&utmdt=About%20Percona&utmhn=www.percona.com&utmhid=1947703805&utmr=0&utmp=/about-us.html&utmac=UA-343802-3&utmcc=__utma%3D154442809.1969570579.1256593671.1256825719.1257805869.3%3B%2B__utmz%3D154442809.1256593671.1.1.utmccn%3D(direct)%7Cutmcsr%3D(direct)%7Cutmcmd%3D(none)%3B%2B',
         bytes          => 35,
         host           => '10.112.2.144',
         pos_in_log     => 55942,
      },
      {
         ts             => '2009-11-09 15:31:09.411349',
         Query_time     => '0.073882',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'www.percona.com',
         arg            => 'get www.percona.com/images/menu_our-vision.gif',
         bytes          => 414,
         host           => '10.112.2.144',
         pos_in_log     => 59213,
      },
      {
         ts             => '2009-11-09 15:31:09.420851',
         Query_time     => '0.067669',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'www.percona.com',
         arg            => 'get www.percona.com/images/bg-gray-corner-top.gif',
         bytes          => 170,
         host           => '10.112.2.144',
         pos_in_log     => 65644,
      },
      {
         ts             => '2009-11-09 15:31:09.420996',
         Query_time     => '0.067345',
         Status_code    => '200',
         Transmit_time  => '0.134909',
         Virtual_host   => 'www.percona.com',
         arg            => 'get www.percona.com/images/handshake.jpg',
         bytes          => 20017,
         host           => '10.112.2.144',
         pos_in_log     => 67956,
      },
      {
         ts             => '2009-11-09 15:31:14.536149',
         Query_time     => '0.061528',
         Status_code    => '200',
         Transmit_time  => '0.059577',
         Virtual_host   => 'hit.clickaider.com',
         arg            => 'get hit.clickaider.com/clickaider.js',
         bytes          => 4009,
         host           => '10.112.2.144',
         pos_in_log     => 147447,
      },
      {
         ts             => '2009-11-09 15:31:14.678713',
         Query_time     => '0.060436',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'hit.clickaider.com',
         arg            => 'get hit.clickaider.com/pv?lng=140&&lnks=&t=About%20Percona&c=73a41b95-2926&r=http%3A%2F%2Fwww.percona.com%2F&tz=-420&loc=http%3A%2F%2Fwww.percona.com%2Fabout-us.html&rnd=3688',
         bytes          => 43,
         host           => '10.112.2.144',
         pos_in_log     => 167245,
      },
      {
         ts             => '2009-11-09 15:31:14.737890',
         Query_time     => '0.061937',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'hit.clickaider.com',
         arg            => 'get hit.clickaider.com/s/forms.js',
         bytes          => 822,
         host           => '10.112.2.144',
         pos_in_log     => 170117,
      },
   ],
);

# A reponse received in out of order packet.
$protocol = new HTTPProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/http/http_tcpdump004.txt',
   result   => [
      {  ts             => '2009-11-12 11:27:10.757573',
         Query_time     => '0.327356',
         Status_code    => '200',
         Transmit_time  => '0.549501',
         Virtual_host   => 'dev.mysql.com',
         arg            => 'get dev.mysql.com/common/css/mysql.css',
         bytes          => 11283,
         host           => '10.67.237.92',
         pos_in_log     => 776,
      },
   ],
);

# A client request broken over 2 packets.
$protocol = new HTTPProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/http/http_tcpdump005.txt',
   result   => [
      {  ts             => '2009-11-13 09:20:31.041924',
         Query_time     => '0.342166',
         Status_code    => '200',
         Transmit_time  => '0.012780',
         Virtual_host   => 'dev.mysql.com',
         arg            => 'get dev.mysql.com/doc/refman/5.0/fr/retrieving-data.html',
         bytes          => 4382,
         host           => '192.168.200.110',
         pos_in_log     => 785, 
      },
   ],
);

# Out of order header that might look like the text header
# but is really data; text header arrives last.
$protocol = new HTTPProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/http/http_tcpdump006.txt',
   result   => [
      {  ts             => '2009-11-13 09:50:44.432099',
         Query_time     => '0.140878',
         Status_code    => '200',
         Transmit_time  => '0.237153',
         Virtual_host   => '247wallst.files.wordpress.com',
         arg            => 'get 247wallst.files.wordpress.com/2009/11/airplane4.jpg?w=139&h=93',
         bytes          => 3391,
         host           => '192.168.200.110',
         pos_in_log     => 782,
      },
   ],
);

# One 2.6M image that took almost a minute to load (very slow wifi).
$protocol = new HTTPProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/http/http_tcpdump007.txt',
   result   => [
      {  ts             => '2009-11-13 10:09:53.251620',
         Query_time     => '0.121971',
         Status_code    => '200',
         Transmit_time  => '40.311228',
         Virtual_host   => 'apod.nasa.gov',
         arg            => 'get apod.nasa.gov/apod/image/0911/Ophcloud_spitzer.jpg',
         bytes          => 2706737,
         host           => '192.168.200.110',
         pos_in_log     => 640,
      }
   ],
);

# A simple POST.
$protocol = new HTTPProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/http/http_tcpdump008.txt',
   result   => [
      {  ts             => '2009-11-13 10:53:48.349465',
         Query_time     => '0.030740',
         Status_code    => '200',
         Transmit_time  => '0.000000',
         Virtual_host   => 'www.google.com',
         arg            => 'post www.google.com/finance/qs/channel?VER=6&RID=481&CVER=1&zx=5xccsz-eg9chk&t=1',
         bytes          => 54,
         host           => '192.168.200.110',
         pos_in_log     => 0,
      }
   ],
);

# .http instead of .80
$protocol = new HTTPProtocolParser();
test_protocol_parser(
   parser   => $tcpdump,
   protocol => $protocol,
   file     => 't/lib/samples/http/http_tcpdump009.txt',
   result   => [
      { ts              => '2009-11-09 11:31:52.341907',
        bytes           => '715',
        host            => '10.112.2.144',
        pos_in_log      => 0,
        Virtual_host    => 'hackmysql.com',
        arg             => 'get hackmysql.com/contact',
        Status_code     => '200',
        Query_time      => '0.651419',
        Transmit_time   => '0.000000',
      },
   ],
);

# #############################################################################
# Done.
# #############################################################################
exit;
