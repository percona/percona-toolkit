#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use Test::More;

use PerconaTest;
use Percona::Toolkit;

my $version  = $Percona::Toolkit::VERSION;

use File::Basename qw(basename);
my @vc_tools = grep { chomp; basename($_) =~ /\A[a-z-]+\z/ } glob("$trunk/bin/*");

foreach my $tool ( @vc_tools ) {
   my $output = `$tool --version 2>/dev/null`;
   my ($tool_version) = $output =~ /(\b[0-9]\.[0-9]\.[0-9]\b)/;
   next unless $tool_version; # Some tools don't have --version implemented
   is(
      $tool_version,
      $version,
      "$tool --version and Percona::Toolkit::VERSION agree"
   );
}

use IPC::Cmd qw(can_run);

my $bzr = can_run('bzr');
SKIP: {
   skip "Can't run bzr, skipping tag checking", 1 unless $bzr;

   my @tags          = split /\n/, `bzr tags`;
   my ($current_tag) = $tags[-1] =~ /^(\S+)/;

   is(
      $current_tag,
      $version,
      "bzr tags and Percona::Toolkit::VERSION agree"
   );
}

done_testing;
