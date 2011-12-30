#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 6;

use Retry;
use PerconaTest;

my $rt = new Retry();

my @called = ();
my @retry  = ();
my @die    = ();

my $try = sub {
   push @called, 'try';
   die if shift @die;
};
my $fail = sub {
   push @called, 'fail';
   return shift @retry;
};
my $wait = sub {
   push @called, 'wait';
};
my $final_fail = sub {
   push @called, 'final_fail';
   return;
};

sub try_it {
   return $rt->retry(
      try        => $try,
      fail       => $fail,
      wait       => $wait,
      final_fail => $final_fail,
   );
}

# Success on first try;
@called = ();
@retry  = ();
@die    = ();
try_it();
is_deeply(
   \@called,
   ['try'],
   'Success on first try'
);

# Success on 2nd try.
@called = ();
@retry  = (1),
@die    = (1);
try_it();
is_deeply(
   \@called,
   ['try', 'fail', 'wait',
    'try'
   ],
   'Success on second try'
);

# Success on 3rd, last try.
@called = ();
@retry  = (1, 1),
@die    = (1, 1);
try_it();
is_deeply(
   \@called,
   ['try', 'fail', 'wait',
    'try', 'fail', 'wait',
    'try'
   ],
   'Success on third, final try'
);

# Failure.
@called = ();
@retry  = (1, 1, 1);
@die    = (1, 1, 1);
try_it();
is_deeply(
   \@called,
   ['try', 'fail', 'wait',
    'try', 'fail', 'wait',
    'try', 'final_fail',
   ],
   'Failure'
);

# Fail and no retry.
@called = ();
@retry  = (0);
@die    = (1);
try_it();
is_deeply(
   \@called,
   ['try', 'fail', 'final_fail'],
   "Fail, don't retry"
);

# #############################################################################
# Done.
# #############################################################################
my $output = '';
{
   local *STDERR;
   open STDERR, '>', \$output;
   $rt->_d('Complete test coverage');
}
like(
   $output,
   qr/Complete test coverage/,
   '_d() works'
);
exit;
