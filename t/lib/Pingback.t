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

use Pingback;

my @requests;
{
   package FakeUA;

   sub new { bless $_[1], $_[0] }
   sub get { shift @{ $_[0] } }
   sub post { push @requests, $_[2]; }
}

my $fake_ua = FakeUA->new([
   { status => 200, content => '$PerconaTest::Pingback::counter++; +{ some => "data" }' },
   { status => 200 },
   { status => 200, content => 'code_that_fails() !!!::,.-' },
]);

$PerconaTest::Pingback::counter = 0;
Pingback::pingback('http://www.percona.com/fake_url', $fake_ua);

is(
   $PerconaTest::Pingback::counter,
   1,
   "If the GET returns with status 200 and there's content, it's executed as Perl code"
);

is(
   scalar @requests,
   1,
   "..and it sends one request"
);

is(
   $requests[0]->{content},
   '{"some":"data"}',
   "..which was obtained through the eval'd text"
);

@requests = ();
Pingback::pingback('http://www.percona.com/fake_url', $fake_ua);

like(
   $requests[0]->{content},
   qr/"perl_version":"$]"/,
   "if the server doesn't return any code, checks the defaults"
);

@requests = ();
Pingback::pingback('http://www.percona.com/fake_url', $fake_ua);

like(
   $requests[0]->{content},
   qr/"perl_version":"$]"/,
   "returns the defaults if the code returned by the server failed"
);

like(
   $requests[0]->{content},
   qr/"check_code_error":/,
   "..plus an item for the error",
);

done_testing;
