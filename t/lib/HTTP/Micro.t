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

use HTTP::Micro;

local $EVAL_ERROR;
eval { require HTTP::Tiny };
if ( $EVAL_ERROR ) {
   plan skip_all => "HTTP::Tiny is not installed";
}

# Need a simple URL that won't try to do chunking.
for my $test_url ( "http://www.percona.com/robots.txt", "https://v.percona.com" ) {
   my $tiny     = HTTP::Tiny->new(max_redirect => 0)->request('GET', $test_url);
   my $micro    = HTTP::Micro->new->request('GET', $test_url);

   like(
      $micro->{content},
      qr/^\Q$tiny->{content}/,
      "HTTP::Micro == HTTP::Tiny for $test_url"
   );
}

done_testing;
exit;
