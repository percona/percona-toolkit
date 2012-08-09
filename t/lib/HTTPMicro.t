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

use HTTP::Tiny;
use HTTPMicro;

my $test_url = "http://www.google.com";
my $tiny  = HTTP::Tiny->new(max_redirect => 0)->request('GET', $test_url);
my $micro = HTTP::Micro->new->request('GET', $test_url);

is_deeply(
   $micro->{content},
   $tiny->{content},
   "HTTP::Micro behaves like HTTP::Tiny (with max_redirect) for $test_url"
);

done_testing;
