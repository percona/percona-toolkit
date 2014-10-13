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
use IPC::Cmd qw(can_run run);

use PerconaTest;
use Percona::Toolkit;

use File::Temp qw(tempfile);

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

   my ($fh, $filename) = tempfile( "pt-version-test-XXXXXXX", UNLINK => 1 );
   print { $fh } "require q{$tool}; print \$Percona::Toolkit::VERSION, qq{\\n}";
   close $fh;
   
   my ($success, undef, $full_buf) =
      run( command => [ $perl, $filename ] );

   if ( !$success ) {
      fail("Failed to get \$Percona::Toolkit::VERSION from $base: " . $full_buf ? join("", @$full_buf) : '')
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
   skip '$trunk and bzr root differ, skipping tag checking', 1
      unless $root eq $trunk;
   
   my @tags          = split /\n/, `$bzr tags`;
   # sort the version numbers (some bzr versions do not sort them)
   @tags = sort { calc_value($a) <=> calc_value($b) } @tags; 
   my ($current_tag) = $tags[-1] =~ /^(\S+)/;

   is(
      $current_tag,
      $version,
      "bzr tags and Percona::Toolkit::VERSION agree"
   );
}

# we use this function to help sort version numbers
sub calc_value {
   my $version = shift;
   $version =~ s/ +[^ ]*$//;
   my $value = 0;
   my $exp = 0;
   foreach my $num (reverse split /\./, $version) {
      $value += $num * 10 ** $exp++;
   }
   print "$version = $value\n";
   return $value;
}


done_testing;
