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

use HTTPMicro;

local $EVAL_ERROR;
eval { require HTTP::Tiny };
if ( $EVAL_ERROR ) {
   plan skip_all => "HTTP::Tiny is not installed, not testing compat";
}

my $test_url = "http://www.google.com";
my $tiny  = HTTP::Tiny->new(max_redirect => 0)->request('GET', $test_url);
my $micro = HTTPMicro->new->request('GET', $test_url);

is_deeply(
   $micro->{content},
   $tiny->{content},
   "HTTPMicro behaves like HTTP::Tiny (with max_redirect) for $test_url"
);

done_testing;
