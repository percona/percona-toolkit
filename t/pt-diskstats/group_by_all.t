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

use DiskstatsGroupByAll;

my $obj = DiskstatsGroupByAll->new();

for my $filename ( map "diskstats-00$_.txt", 1..5 ) {
   my $expected = load_file(
               File::Spec->catfile( "t", "pt-diskstats", "expected", "all_$filename"),
            );
   
   my $got = output(
      sub {
         my $orig_re = $obj->column_regex();
         $obj->column_regex(qr/./);
         $obj->group_by_all(
            filename => File::Spec->catfile( $trunk, "t", "pt-diskstats", "samples", $filename ),
         );
         $obj->column_regex($orig_re);
      });
   
   is($got, $expected, "$filename via filename");

   $got = output(
      sub {
         my $orig_re = $obj->column_regex();
         $obj->column_regex(qr/./);
         open my $fh, "<", File::Spec->catfile( $trunk, "t", "pt-diskstats", "samples", $filename ) or die $!;
         $obj->group_by_all(
            filehandle => $fh,
         );
         $obj->column_regex($orig_re);
      });

   is($got, $expected, "$filename via filehandle");

   $got = output(
      sub {
         my $orig_re = $obj->column_regex();
         $obj->column_regex(qr/./);
         $obj->group_by_all(
            data => load_file( File::Spec->catfile( "t", "pt-diskstats", "samples", $filename ) ),
         );
         $obj->column_regex($orig_re);
      });

   is($got, $expected, "$filename via data");

   $obj->filename( File::Spec->catfile( $trunk, "t", "pt-diskstats", "samples", $filename ) );
   $got = output(
      sub {
         my $orig_re = $obj->column_regex();
         $obj->column_regex(qr/./);
         $obj->group_by_all();
         $obj->column_regex($orig_re);
      });

   is($got, $expected, "$filename via obj->filename()");

}
