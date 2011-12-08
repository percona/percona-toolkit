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

use PerconaTest;

use DiskstatsGroupByDisk;

use File::Basename qw( dirname );
use File::Spec;

my $filename = File::Spec->catfile( "t", "pt-diskstats", "samples",  "diskstats-001.txt" );
my $obj = DiskstatsGroupByDisk->new( filename => $filename );

{
   my $expected = <<'EOF';
  #ts device          rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  {4} ram0             0.0     0.0     0.0     0%    0.0     0.0     0.0     0.0     0.0     0%    0.0     0.0   0%      0
  {4} cciss/c0d0       0.0     0.0     0.0     0%    0.0     0.0    17.7    56.2     0.5    86%    0.0     0.6   0%      0
  {4} cciss/c0d0p1     0.0     0.0     0.0     0%    0.0     0.0     0.0     0.0     0.0     0%    0.0     0.0   0%      0
  {4} cciss/c0d0p2     0.0     0.0     0.0     0%    0.0     0.0    17.7    56.2     0.5    86%    0.0     0.6   0%      0
  {4} cciss/c0d1     458.1    43.0     9.6     0%   11.5    25.1   985.0    48.4    23.3     0%    0.1     0.1 102%      0
  {4} cciss/c1d0       0.0     0.0     0.0     0%    0.0     0.0     0.0     0.0     0.0     0%    0.0     0.0   0%      0
  {4} dm-0             0.0     0.0     0.0     0%    0.0     0.0    99.3     8.0     0.4     0%    0.1     0.7   0%      0
  {4} md0              0.0     0.0     0.0     0%    0.0     0.0     0.0     0.0     0.0     0%    0.0     0.0   0%      0
EOF

   my $got = output(
   sub {
      my $orig_re = $obj->column_regex();
      $obj->column_regex(qr/./);
      $obj->group_by_disk();
      $obj->column_regex($orig_re);
   });
   
   is($got, $expected, "Default settings get us what we want");
}

{
   my $expected = <<'EOF';
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  {5} sda3    1394.1    32.0    21.8     1%    0.5     0.4    98.8    62.8     3.0    48%    0.0     0.3  41%      0
  {5} sda4    1394.1    32.0    21.8     1%    0.5     0.4    98.8    62.8     3.0    48%    0.0     0.3  41%      0
EOF

   $obj->filename( File::Spec->catfile( "t", "pt-diskstats", "samples", "diskstats-005.txt") );

   my $got = output(
   sub {
      my $orig_re = $obj->column_regex();
      $obj->column_regex(qr/./);
      $obj->group_by_disk();
      $obj->column_regex($orig_re);
   });
   
   is($got, $expected, "diskstats-005.txt");
}


{
   my $expected = <<'EOF';
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  {5} sda3    1394.1    32.0    21.8     1%    0.5     0.4    98.8    62.8     3.0    48%    0.0     0.3  41%      0
  {5} sda4    1394.1    32.0    21.8     1%    0.5     0.4    98.8    62.8     3.0    48%    0.0     0.3  41%      0
EOF


   my $file = <<'EOF';
TS 1298130002.073935000
EOF

   my $filename = File::Spec->catfile( "t", "pt-diskstats", "samples", "diskstats-005.txt");
   my $fake_file .= do { open my $fh, "<", $filename or die $!; local $/; <$fh>; };

   open my $in_fh,  "<", \$fake_file or die $!;
   open my $out_fh, ">", \my $got or die $!;
   $obj->out_fh($out_fh);
   {
      my $orig_re = $obj->column_regex();
      $obj->column_regex(qr/./);
      $obj->group_by_disk( filehandle => $in_fh );
      $obj->column_regex($orig_re);
   }
   close($out_fh);
   close($in_fh);

   is( $got, $expected, "diskstats-005.txt with TS" );
}

{
   my $data = <<'EOF';
TS 1297205887.156653000
   1    0 ram0 0 0 0 0 0 0 0 0 0 0 0
TS 1297205888.161613000
EOF

   my $got = output(
   sub{
      my $orig_re = $obj->column_regex();
      $obj->column_regex(qr/./);
      $obj->group_by_disk(data => $data);
      $obj->column_regex($orig_re);
   });
   
   ok(!$got);
}

{
   my $expected = <<'EOF';
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg
  {1} ram0       1.0     1.0     0.0    50%    0.0     1.0     1.0     1.0     0.0    50%    0.0     1.0   0%      0
EOF

   my $data = <<'EOF';
   1    0 ram0 0 0 0 0 0 0 0 0 0 0 0
TS 1297205887.156653000
   1    0 ram0 1 1 1 1 1 1 1 1 1 1 1
TS 1297205888.161613000
EOF

   my $got = output(
   sub {
      my $orig_re = $obj->column_regex();
      $obj->column_regex(qr/./);
      $obj->group_by_disk(data => $data);
      $obj->column_regex($orig_re);
   });

   is($got, $expected);
}

for my $filename ( map "diskstats-00$_.txt", 2..4 ) {
   my $expected = load_file(
               File::Spec->catfile( "t", "pt-diskstats", "expected", "disk_$filename"),
            );
   
   my $got = output(
      sub {
         my $orig_re = $obj->column_regex();
         $obj->column_regex(qr/./);
         $obj->group_by_disk(
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
         $obj->group_by_disk(
            filehandle => $fh,
         );
         $obj->column_regex($orig_re);
      });

   is($got, $expected, "$filename via filehandle");

   $got = output(
      sub {
         my $orig_re = $obj->column_regex();
         $obj->column_regex(qr/./);
         $obj->group_by_disk(
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
         $obj->group_by_disk();
         $obj->column_regex($orig_re);
      });

   is($got, $expected, "$filename via obj->filename()");
}

