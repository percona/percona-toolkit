#!/usr/bin/perl

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

use File::Spec;

BEGIN {
   use_ok "Diskstats";
   use_ok "DiskstatsGroupByAll";
   use_ok "DiskstatsGroupByDisk";
   use_ok "DiskstatsGroupBySample";
}

my $obj = new_ok("Diskstats");

can_ok( $obj, qw(
                  out_fh column_regex device_regex filename
                  block_size sorted_devs clear_state clear_sorted_devs
                  stats_for previous_stats_for first_stats_for
                  has_stats design_print_formats parse_diskstats_line
                  parse_from print_deltas
               ) );

my $line = "104    0 cciss/c0d0 2139885 162788 37361471 8034486 17999682 83425310 811400340 12711047 0 6869437 20744582";

my %expected_results = (
      'major'              => 104,
      'minor'              => 0,

      'reads'              => 2139885,
      'reads_merged'       => 162788,
      'read_sectors'       => 37361471,
      'ms_spent_reading'   => 8034486,
      'read_bytes'         => 19129073152,
      'read_kbs'           => 18680735.5,

      'writes'             => 17999682,
      'writes_merged'      => 83425310,
      'written_sectors'    => 811400340,
      'ms_spent_writing'   => 12711047,
      'written_bytes'      => 415436974080,
      'written_kbs'        => 405700170,

      'ios_in_progress'    => 0,
      'ms_spent_doing_io'  => 6869437,
      'ms_weighted'        => 20744582,

      'ttbyt'              => 434566047232,
      'ttreq'              => 20139567,
);

# Copypasted from Diskstats.pm. If the one in there changes so should this.
my @columns_in_order = (
   # Colum        # Format   # Key name
   [ "   rd_s" => "%7.1f",   "reads_sec",          ],
   [ "rd_avkb" => "%7.1f",   "avg_read_sz",        ],
   [ "rd_mb_s" => "%7.1f",   "mbytes_read_sec",    ],
   [ "rd_mrg"  => "%5.0f%%", "read_merge_pct",     ],
   [ "rd_cnc"  => "%6.1f",   "read_conc",          ],
   [ "  rd_rt" => "%7.1f",   "read_rtime",         ],
   [ "   wr_s" => "%7.1f",   "writes_sec",         ],
   [ "wr_avkb" => "%7.1f",   "avg_write_sz",       ],
   [ "wr_mb_s" => "%7.1f",   "mbytes_written_sec", ],
   [ "wr_mrg"  => "%5.0f%%", "write_merge_pct",    ],
   [ "wr_cnc"  => "%6.1f",   "write_conc",         ],
   [ "  wr_rt" => "%7.1f",   "write_rtime",        ],
   [ "busy"    => "%3.0f%%", "busy",               ],
   [ "in_prg"  => "%6d",     "in_progress",        ],
);

my ($dev, $res) = $obj->parse_diskstats_line($line, $obj->block_size);

is_deeply( $res, \%expected_results, "parse_diskstats_line works" );

$obj->column_regex(qr/./);
my ($header, $rest, $cols) = $obj->design_print_formats();
is($header, join(" ", q{%5s %-6s}, map { $_->[0] } @columns_in_order),
         "design_print_formats: sanity check for defaults");

($header, $rest, $cols) = $obj->design_print_formats(max_device_length => 10);
my $all_columns_format = join(" ", q{%5s %-10s}, map { $_->[0] } @columns_in_order);
is($header, $all_columns_format, "design_print_formats: max_device_length works");

$obj->column_regex(qr/(?!)/); # Will never match
($header, $rest, $cols) = $obj->design_print_formats(max_device_length => 10);
is($header, q{%5s %-10s }, "design_print_formats respects column_regex");

$obj->column_regex(qr//);
($header, $rest, $cols) = $obj->design_print_formats(max_device_length => 10, columns => []);
is($header, q{%5s %-10s }, "...unless we pass an explicit column array");

$obj->column_regex(qr/./);
($header, $rest, $cols) = $obj->design_print_formats(
                                 max_device_length => 10,
                                 columns           => [qw( busy )]
                           );
is($header, q{%5s %-10s busy}, "");

($header, $rest, $cols) = $obj->design_print_formats(
                                 max_device_length => 10,
                                 columns           => [map { $_->[0] } @columns_in_order],
                           );
is($header, $all_columns_format, "");

throws_ok( sub { $obj->design_print_formats( columns => {} ) },
        qr/The columns argument to design_print_formats should be an arrayref/,
        "design_print_formats dies when passed an invalid columns argument");

for my $meth ( qw( current_ts previous_ts first_ts ) ) {
   ok(!$obj->$meth(), "Diskstats->$meth is initially false");

   $obj->$meth(10);
   is($obj->$meth(), 10, "Diskstats->$meth(10) sets it to 10");

   $obj->$meth(20);
   $obj->clear_ts();
   ok(!$obj->$meth(), "Diskstats->clear_ts does as advertized");
}

is($obj->out_fh(), \*STDOUT, "by default, outputs to STDOUT");
open my $fh, "<", \my $tmp;
$obj->out_fh($fh);
is($obj->out_fh(), $fh, "Changing it works");
close($fh);
is($obj->out_fh(), \*STDOUT, "and if we close the set filehandle, it reverts to STDOUT");


is_deeply([$obj->sorted_devs()], [], "sorted_devs starts empty");

$obj->add_sorted_devs("sda");
is_deeply([$obj->sorted_devs()], [qw(sda)], "We can add devices just fine,");

$obj->add_sorted_devs("sda");
is_deeply([$obj->sorted_devs()], [qw(sda)], "...And duplicates get detected and discarded");

$obj->clear_sorted_devs();
is_deeply([$obj->sorted_devs()], [], "clear_sorted_devs does as advertized,");
$obj->add_sorted_devs("sda");
is_deeply([$obj->sorted_devs()], [qw(sda)], "...And clears the internal duplicate-checking list");



# Common tests for all three subclasses
for my $test (
      {
         class               => "DiskstatsGroupByAll",
         method              => "group_by_all",
         results_file_prefix => "all",
      },
      {
         class               => "DiskstatsGroupByDisk",
         method              => "group_by_disk",
         results_file_prefix => "disk",
      },
      {
         class               => "DiskstatsGroupBySample",
         method              => "group_by_sample",
         results_file_prefix => "sample",
      }) {
   my $obj    = $test->{class}->new();
   my $method = $test->{method};
   my $prefix = $test->{results_file_prefix};

   for my $filename ( map "diskstats-00$_.txt", 1..5 ) {
      my $file = File::Spec->catfile( "t", "pt-diskstats", "samples", $filename );
      my $file_with_trunk = File::Spec->catfile( $trunk, $file );

      my $expected = load_file( File::Spec->catfile( "t", "pt-diskstats", "expected", "${prefix}_$filename" ) );
      
      my $got = output(
         sub {
            my $orig_re = $obj->column_regex();
            $obj->column_regex(qr/./);
            $obj->$method(
               filename => $file_with_trunk,
            );
            $obj->column_regex($orig_re);
         });
      
      is($got, $expected, "$method: $filename via filename");
   
      $got = output(
         sub {
            my $orig_re = $obj->column_regex();
            $obj->column_regex(qr/./);
            open my $fh, "<", $file_with_trunk or die $!;
            $obj->$method(
               filehandle => $fh,
            );
            $obj->column_regex($orig_re);
         });
   
      is($got, $expected, "$method: $filename via filehandle");
   
      $got = output(
         sub {
            my $orig_re = $obj->column_regex();
            $obj->column_regex(qr/./);
            $obj->$method(
               data => load_file( $file ),
            );
            $obj->column_regex($orig_re);
         });
   
      is($got, $expected, "$method: $filename via data");
   
      $got = output(
         sub {
            my $orig_re = $obj->column_regex();
            $obj->column_regex(qr/./);
            $obj->$method(
               data => "TS 1298130002.073935000\n" . load_file( $file ),
            );
            $obj->column_regex($orig_re);
         });
   
      is($got, $expected, "$method: $filename with an extra TS at the top");
   
      $obj->filename( $file_with_trunk );
      $got = output(
         sub {
            my $orig_re = $obj->column_regex();
            $obj->column_regex(qr/./);
            $obj->$method();
            $obj->column_regex($orig_re);
         });
   
      is($got, $expected, "$method: $filename via obj->filename()");

      my $data = <<'EOF';
TS 1297205887.156653000
   1    0 ram0 0 0 0 0 0 0 0 0 0 0 0
TS 1297205888.161613000
EOF

      $got = output(
      sub{
         my $orig_re = $obj->column_regex();
         $obj->column_regex(qr/./);
         $obj->$method(data => $data);
         $obj->column_regex($orig_re);
      });
      
      ok(!$got, "$method: 1 line of data between two TS lines results in no output");

   }
}