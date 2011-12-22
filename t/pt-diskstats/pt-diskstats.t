#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More qw( no_plan );
use File::Spec;

use PerconaTest;
use pt_diskstats;

{
# Tie magic. During the tests we tie STDIN to always return a lone "q".
# See the note in the bottom of this file about *DATA. Please don't close it.
sub Test::TIEHANDLE {
   return bless {}, "Test";
}

sub Test::FILENO {
   return fileno(*DATA);
}

sub Test::READLINE {
   return "q";
}
}

for my $ext ( qw( all disk sample ) ) {
   for my $filename ( map "diskstats-00$_.txt", 1..5 ) {
      my $expected = load_file(
                        File::Spec->catfile( "t", "pt-diskstats",
                                             "expected", "${ext}_int_$filename"
                                           ),
                     );
      
      my $got = output( sub {
         tie local *STDIN, "Test";
         my $file = File::Spec->catfile( $trunk, "t", "pt-diskstats",
                                             "samples", $filename );
         pt_diskstats::main(
                  "--group-by" => $ext,
                  "--columns"  => "cnc|rt|mb|busy|prg",
                  "--zero-rows",
                  $file
               );
      } );
   
      is($got, $expected, "--group-by $ext for $filename gets the same results as the shell version");
   }
}

__DATA__
Leave this here!
We tie STDIN during the tests, and fake the fileno by giving it *DATA's result;
These lines here make Perl leave *DATA open.

