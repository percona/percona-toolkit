#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

# locale, so test could run on any machine
use POSIX qw(locale_h);
use locale;
my $old_locale;

# query and save the old locale
$old_locale = setlocale(LC_NUMERIC);
setlocale(LC_NUMERIC, "en_US.UTF-8");

use PerconaTest;

my ($tool) = $PROGRAM_NAME =~ m/([\w-]+)\.t$/;

use Test::More tests => 5;

for my $i (2..3,5..7) {
   ok(
      no_diff(
         sub { print `$trunk/bin/pt-summary --read-samples "$trunk/t/pt-summary/samples/Linux/00$i/" | tail -n+3 | tee /home/sveta//tmp/pt-summary/output_00$i.txt` },
         "t/pt-summary/samples/Linux/output_00$i.txt"),
      "--read-samples samples/Linux/00$i works",
   );
}

setlocale(LC_NUMERIC, $old_locale);

exit;
