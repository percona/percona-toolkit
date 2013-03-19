#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
require "$trunk/bin/pt-fk-error-logger";

# #############################################################################
# Test get_fk_error().
# #############################################################################
sub test_get_fk_error {
   my ( $file, $expected_ts, $expected_fke_file ) = @_;
   my $contents = load_file('t/pt-fk-error-logger/'.$file);
   chomp $contents;
   my ($ts, $fke) = pt_fk_error_logger::get_fk_error($contents);
   is(
      $ts,
      $expected_ts,
      "$file timestamp"
   );
   my $expected_fke = load_file('t/pt-fk-error-logger/'.$expected_fke_file);
   chomp $expected_fke;
   is(
      $fke,
      $expected_fke,
      "$file foreign key error text"
   );
   return;
}

test_get_fk_error(
   'samples/is001.txt',
   '070913 11:06:03',
   'samples/is001-fke.txt'
);

test_get_fk_error(
   'samples/is002.txt',
   '070915 15:10:24',
   'samples/is002-fke.txt'
);

test_get_fk_error(
   'samples/is003.txt',
   '070915 16:15:55',
   'samples/is003-fke.txt'
);

test_get_fk_error(
   'samples/is004.txt',
   '070915 16:23:09',
   'samples/is004-fke.txt'
);

test_get_fk_error(
   'samples/is005.txt',
   '070915 16:31:46',
   'samples/is005-fke.txt'
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
