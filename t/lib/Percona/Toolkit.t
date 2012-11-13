#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use Test::More;

use IPC::Cmd qw(run can_run);

use PerconaTest;
use Percona::Toolkit;

my $version  = $Percona::Toolkit::VERSION;

my $perl = $^X;

use File::Basename qw(basename);
my @vc_tools = grep { chomp; basename($_) =~ /\A[a-z-]+\z/ } glob("$trunk/bin/*");

foreach my $tool ( @vc_tools ) {
   my $output = `$tool --version 2>/dev/null`;
   my ($tool_version) = $output =~ /(\b[0-9]\.[0-9]\.[0-9]\b)/;
   next unless $tool_version; # Some tools don't have --version implemented
   my $base = basename($tool);
   is(
      $tool_version,
      $version,
      "$base --version and Percona::Toolkit::VERSION agree"
   );

   # Now let's check that lib/Percona/Toolkit.pm and each tool's
   # $Percona::Toolkit::VERSION agree, sow e can avoid the 2.1.4 pt-table-sync
   # debacle
   open my $tmp_fh, q{<}, $tool or die "$!";
   my $is_perl = scalar(<$tmp_fh>) =~ /perl/;
   close $tmp_fh;

   next unless $is_perl;

   my ($success, undef, $full_buf) =
      run(
         command => [ $perl, '-le', "require q{$tool}; print \$Percona::Toolkit::VERSION"]
      );

   if ( !$success ) {
      fail("Failed to get \$Percona::Toolkit::VERSION from $base: $full_buf")
   }
   else {
      chomp(@$full_buf);
      my $out = join "", @$full_buf;
      if ($out) {
         is(
            "@$full_buf",
            $version,
            "$base and lib/Percona/Toolkit.pm agree"
         );
      }
   }
}

my $bzr = can_run('bzr');
SKIP: {
   skip "Can't run bzr, skipping tag checking", 1 unless $bzr;
   chomp(my $root = `$bzr root 2>/dev/null`);
   skip '$trunk and bzr root differ, skipping tag checking'
      unless $root eq $trunk;
   
   my @tags          = split /\n/, `$bzr tags`;
   my ($current_tag) = $tags[-1] =~ /^(\S+)/;

   is(
      $current_tag,
      $version,
      "bzr tags and Percona::Toolkit::VERSION agree"
   );
}

done_testing;
