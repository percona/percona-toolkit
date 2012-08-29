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

use File::Spec;
use File::Temp ();

use PerconaTest;
use OptionParser;

BEGIN {
   use_ok "Diskstats";
   use_ok "DiskstatsGroupByAll";
   use_ok "DiskstatsGroupByDisk";
   use_ok "DiskstatsGroupBySample";
}

my $o = new OptionParser(description => 'Diskstats');
$o->get_specs("$trunk/bin/pt-diskstats");
$o->get_opts();

{
my $obj = new Diskstats(OptionParser => $o);

can_ok( $obj, qw(
                  columns_regex devices_regex filename
                  block_size ordered_devs clear_state clear_ordered_devs
                  stats_for prev_stats_for first_stats_for
                  has_stats design_print_formats parse_diskstats_line
                  parse_from print_deltas
               ) );

# ############################################################################
# Testing the constructor.
# ############################################################################
for my $attr (
      [ filename     => (File::Temp::tempfile($0.'diskstats.XXXXXX',
                                              OPEN=>0, UNLINK=>1))[1] ],
      [ columns_regex  => qr/!!!/  ],
      [ devices_regex  => qr/!!!/  ],
      [ block_size    => 215      ],
      [ show_inactive => 1        ],
      [ sample_time   => 1        ],
      [ interactive   => 1        ],
   ) {
   my $attribute   = $attr->[0];
   my $value       = $attr->[1];
   my $test_obj    = Diskstats->new( @$attr, OptionParser => $o );

   is(
      $test_obj->$attribute(),
      $value,
      "Passing an explicit [$attribute] to the constructor works",
   );
}

# ############################################################################
# parse_diskstats_line
# ############################################################################
for my $test (
   [
      "104    0 cciss/c0d0 2139885 162788 37361471 8034486 17999682 83425310 811400340 12711047 0 6869437 20744582",
      [
         104, 0, "cciss/c0d0",   # major, minor, device
      
         2139885,     # reads
         162788,      # reads_merged
         37361471,    # read_sectors
         8034486,     # ms_spent_reading
      
         17999682,    # writes
         83425310,    # writes_merged
         811400340,   # written_sectors
         12711047,    # ms_spent_writing
      
         0,           # ios_in_progress
         6869437,     # ms_spent_doing_io
         20744582,    # ms_weighted
      
         18680735.5,  # read_kbs
         405700170,   # written_kbs
         103727665,    # ios_requested
         434566047232,# ios_in_bytes
      ],
      "parse_diskstats_line works"
   ],
   [
      "  8 33 sdc1 1572537676 2369344 3687151364 1575056414 2541895139 1708184481 3991989096 121136333 1 982122453 1798311795",
      [
          '8', '33', 'sdc1', 1572537676, '2369344', 3687151364,
          '1575056414', 2541895139, '1708184481', 3991989096,
          '121136333', '1', '982122453', '1798311795', '1843575682',
          '1995994548', 5824986640, '3931719915520'
      ],
      "parse_diskstats_line works"
   ],
   [
      "  8 33 sdc1 1572537676 2369344 3687151364 1575056414 2541895139 1708184481 3991989096 121136333 1 982122453 1798311795\n",
      [
          '8', '33', 'sdc1', 1572537676, '2369344', 3687151364,
          '1575056414', 2541895139, '1708184481', 3991989096,
          '121136333', '1', '982122453', '1798311795',
          '1843575682',
          '1995994548', 5824986640, '3931719915520'
      ],
      "parse_diskstats_line ignores a trailing newline"
   ],
   [
      "  8 33 sdc1 1572537676 2369344 3687151364 1575056414 2541895139 1708184481 3991989096 121136333 1 982122453 \n",
      undef,
      "parse_diskstats_line fails on a line without enough fields"
   ],
   [
      "  8 33 sdc1 1572537676 2369344 3687151364 1575056414 2541895139 1708184481 3991989096 121136333 1 982122453 12224123 12312312",
      undef,
      "parse_diskstats_line fails on a line with too many fields"
   ],
   [
      "",
      undef,
      "parse_diskstats_line returns undef on an empty string",
   ],
   [
      "Malformed line",
      undef,
      "parse_diskstats_line returns undef on a malformed line",
   ],
) {
   my ($line, $expected_results, $desc) = @$test;
   my ($dev, $res) = $obj->parse_diskstats_line($line, $obj->block_size);
   is_deeply( $res, $expected_results, $desc );
}

# For speed, ->parse_diskstats_line doesn't check for undef.
# In any case, this should never happen, since it's internally
# used within a readline() loop.
local $EVAL_ERROR;
eval { $obj->parse_diskstats_line(undef, $obj->block_size); };
like(
   $EVAL_ERROR,
   qr/Use of uninitialized value/,
   "parse_diskstats_line should fail on undef",
);


# ############################################################################
# design_print_formats
# ############################################################################

my @columns_in_order = @Diskstats::columns_in_order;

$obj->set_columns_regex(qr/./);
my ($header, $rows, $cols) = $obj->design_print_formats();
is_deeply(
   $cols,
   [ map { $_->[0] } @columns_in_order ],
   "design_print_formats: returns the expected columns"
);

                  # qr/ \A (?!.*io_s$|\s*[qs]time$) /x
$obj->set_columns_regex(qr/cnc|rt|busy|prg|[mk]b|[dr]_s|mrg/);
($header, $rows, $cols) = $obj->design_print_formats();
is(
   $header,
   join(" ", q{%+*s %-6s}, grep { $_ =~ $obj->columns_regex() } map { $_->[0] } @columns_in_order),
   "design_print_formats: sanity check for defaults"
);

$obj->set_columns_regex(qr/./);
($header, $rows, $cols) = $obj->design_print_formats(max_device_length => 10);
my $all_columns_format = join(" ", q{%+*s %-10s}, map { $_->[0] } @columns_in_order);
is(
   $header,
   $all_columns_format,
   "design_print_formats: max_device_length works"
);

$obj->set_columns_regex(qr/(?!)/); # Will never match
($header, $rows, $cols) = $obj->design_print_formats(max_device_length => 10);
is(
   $header,
   q{%+*s %-10s },
   "design_print_formats respects columns_regex"
);

$obj->set_columns_regex(qr/./);
($header, $rows, $cols) = $obj->design_print_formats(
                                    max_device_length => 10,
                                    columns           => []
                                 );
is(
   $header,
   q{%+*s %-10s },
   "...unless we pass an explicit column array"
);

$obj->set_columns_regex(qr/./);
($header, $rows, $cols) = $obj->design_print_formats(
                                 max_device_length => 10,
                                 columns           => [qw( busy )]
                           );
is(
   $header,
   q{%+*s %-10s busy},
   "Header"
);

($header, $rows, $cols) = $obj->design_print_formats(
                                 max_device_length => 10,
                                 columns           =>
                                    [ map  { $_->[0] } @columns_in_order ],
                           );
is(
   $header,
   $all_columns_format,
   "All columns format"
);

throws_ok( sub { $obj->design_print_formats( columns => {} ) },
        qr/The columns argument to design_print_formats should be an arrayref/,
        "design_print_formats dies when passed an invalid columns argument");

# ############################################################################
# timestamp methods
# ############################################################################
for my $method ( qw( curr_ts prev_ts first_ts ) ) {
   my $setter = "set_$method";
   ok(!$obj->$method(), "Diskstats->$method is initially false");

   $obj->$setter(10);
   is($obj->$method(), 10, "Diskstats->$setter(10) sets it to 10");

   $obj->$setter(20);
   $obj->clear_ts();
   ok(!$obj->$method(), "Diskstats->clear_ts does as advertized");
}

# ############################################################################
# Adding, removing and listing devices.
# ############################################################################
is_deeply(
   [ $obj->ordered_devs() ],
   [],
   "ordered_devs starts empty"
);

$obj->add_ordered_dev("sda");
is_deeply(
   [ $obj->ordered_devs() ],
   [ qw( sda ) ],
   "We can add devices just fine,"
);

$obj->add_ordered_dev("sda");
is_deeply(
   [ $obj->ordered_devs() ],
   [ qw( sda ) ],
   "...And duplicates get detected and discarded"
);

$obj->clear_ordered_devs();
is_deeply(
   [ $obj->ordered_devs() ],
   [],
   "clear_ordered_devs does as advertized,"
);
$obj->add_ordered_dev("sda");
is_deeply(
   [ $obj->ordered_devs() ],
   [ qw( sda ) ],
   "...And clears the internal duplicate-checking list"
);

# ############################################################################
# show_inactive -- Whenever it prints inactive devices.
# ############################################################################
##
## show_inactive now functions inside parse_from
##
#$obj->set_show_inactive(0);
#my $print_output = output(
#   sub {
#      $obj->print_rows(
#            "SHOULDN'T PRINT THIS",
#            [ qw( a b c ) ],
#            { a => 0, b => 0, c => 0, d => 10 }
#         );
#   }
#);
#$obj->set_show_inactive(1);
#
#is(
#   $print_output,
#   "",
#   "->show_inactive works"
#);

# ############################################################################
# Sane defaults and fatal errors
# ############################################################################
for my $method ( qw( delta_against delta_against_ts group_by ) ) {
   throws_ok(
      sub { Diskstats->$method() },
      qr/\QYou must override $method() in a subclass\E/,
      "->$method has to be overriden"
   );
}

is(
   $obj->compute_line_ts( first_ts => 0 ),
   sprintf( "%5.1f", 0 ),
   "compute_line_ts has a sane default",
);

$obj->set_force_header(0);

is(
   output( sub { $obj->print_header("asdasdas") } ),
   "",
   "force_header works"
);

my $output = output(
   sub { $obj->parse_from( data => "ASMFHNASJNFASKLFLKHNSKD" ); },
   stderr => 1,
);

is(
   $output,
   "",
   "Doesn't die parsing unknown line"
);

# ############################################################################
# _calc* methods
# ############################################################################

$obj->clear_state();

my $prev = {
   TS   => 1281367519,
   data => ($obj->parse_diskstats_line(
"104    0 cciss/c0d0 2139885 162788 37361471 8034486 17999682 83425310 811400340 12711047 0 6869437 20744582", $obj->block_size))[1]
};
my $curr = {
   TS   => 1281367521,
   data => ($obj->parse_diskstats_line(
"104    0 cciss/c0d0 2139886 162790 37361478 8034489 17999738 83425580 811402798 12711097 3 6869449 20744632", $obj->block_size))[1]
};

$obj->first_ts( $prev->{TS} );
$obj->prev_ts( $prev->{TS} );
$obj->curr_ts( $curr->{TS} );

my $deltas = $obj->_calc_delta_for($curr->{data}, $prev->{data});

is_deeply(
   $deltas,
   {
      ms_spent_doing_io => 12,
      ms_spent_reading => 3,
      ms_spent_writing => 50,
      ms_weighted => 50,
      read_kbs => 3.5,
      read_sectors => 7,
      reads => 1,
      reads_merged => 2,
      writes => 56,
      writes_merged => 270,
      written_kbs => 1229,
      written_sectors => 2458,
      ios_in_bytes   => 1262080,
      ios_requested  => 329,
      ios_in_progress => 3,
   },
   "_calc_delta_for works"
);

local $EVAL_ERROR;
eval { $obj->_calc_delta_for($curr->{data}, []) };
ok(!$EVAL_ERROR, "_calc_delta_for guards against undefined values");

my %read_stats = $obj->_calc_read_stats(
   delta_for     => $deltas,
   elapsed       => $curr->{TS} - $prev->{TS},
   devs_in_group => 1,
);

is_deeply(
   \%read_stats,
   {
      avg_read_sz => '3.5',
      mbytes_read_sec => '0.001708984375',
      read_conc => '0.0015',
      read_merge_pct => '66.6666666666667',
      read_requests => 3,
      read_rtime => 1,
      reads_sec => '0.5'
   },
   "_calc_read_stats works"
);

my %write_stats = $obj->_calc_write_stats(
   delta_for     => $deltas,
   elapsed       => $curr->{TS} - $prev->{TS},
   devs_in_group => 1,
);

is_deeply(
   \%write_stats,
   {
      avg_write_sz => '21.9464285714286',
      mbytes_written_sec => '0.60009765625',
      write_conc => '0.025',
      write_merge_pct => '82.8220858895706',
      write_requests => 326,
      write_rtime => '0.153374233128834',
      writes_sec => '28',
   },
   "_calc_write_stats works"
);

my %misc_stats = $obj->_calc_misc_stats(
   delta_for     => $deltas,
   elapsed       => $curr->{TS} - $prev->{TS},
   devs_in_group => 1,
   stats         => { %write_stats, %read_stats },
);

is_deeply(
   \%misc_stats,
   {
      busy => '0.6',
      line_ts => '  0.0',
      qtime => '0.114128245504816',
      s_spent_doing_io => '28.5',
      stime => '0.0364741641337386',
   },
   "_calc_misc_stats works"
);

# Bug 928226: IOS IN PROGRESS can be negative due to kernel bugs,
# which can eventually cause a division by zero if it happens to
# be the negative of the number of ios.
# The tool should return zero in that case, rather than dying.
$deltas->{ios_in_progress} = -$deltas->{ios_requested};
%misc_stats = $obj->_calc_misc_stats(
   delta_for     => $deltas,
   elapsed       => $curr->{TS} - $prev->{TS},
   devs_in_group => 1,
   stats         => { %write_stats, %read_stats },
);

is_deeply(
   \%misc_stats,
   {
      busy => '0.6',
      line_ts => '  0.0',
      qtime => 0,
      s_spent_doing_io => '28.5',
      stime => '0.0364741641337386',
   },
   "_calc_misc_stats works around a negative the IOS IN PROGRESS"
);

$obj->clear_state();

}

# ############################################################################
# The three subclasses
# ############################################################################
for my $test (
      {
         class               => "DiskstatsGroupByAll",
         results_file_prefix => "all",
      },
      {
         class               => "DiskstatsGroupByDisk",
         results_file_prefix => "disk",
      },
      {
         class               => "DiskstatsGroupBySample",
         results_file_prefix => "sample",
      },
) {
   my $obj    = $test->{class}->new(OptionParser => $o, show_inactive => 1);
   my $prefix = $test->{results_file_prefix};

   $obj->set_columns_regex(qr/./);
   $obj->set_show_inactive(1);
   $obj->set_show_timestamps(0);
   $obj->set_automatic_headers(0);
   $obj->set_show_line_between_samples(0);

   for my $filename ( map "diskstats-00$_.txt", 1..5 ) {
      my $file = File::Spec->catfile(qw(t pt-diskstats samples), $filename);
      my $file_with_trunk = File::Spec->catfile($trunk, $file);
      my $expected = "t/pt-diskstats/expected/${prefix}_$filename";

      ok(
         no_diff(
            sub { $obj->group_by(filename => $file_with_trunk); },
            $expected,
         ),
         "group_by $prefix: $filename via filename"
      );

      ok(
         no_diff(
            sub {
               open my $fh, "<", $file_with_trunk or die $!; # "<">"
               $obj->group_by(filehandle => $fh);
            },
            $expected,
         ),
         "group_by $prefix: $filename via filehandle"
      );

      ok(
         no_diff( 
            sub {
               $obj->group_by(
                  data => "TS 1298130002.073935000\n" . load_file( $file ),
               );
            },
            $expected,
         ),
         "group_by $prefix: $filename with an extra TS at the top"
      );
   }

   my $data = <<'EOF';
TS 1297205887.156653000
   1    0 ram0 0 0 0 0 0 0 0 0 0 0 0
TS 1297205888.161613000
EOF
   
   my $got = output( sub { $obj->group_by(data => $data) }, stderr => 1 );
   is(
      $got,
      '',
      "group_by $prefix: 1 line of data between two TS lines results in no output"
   );

   $obj->set_curr_ts(0);
   $obj->set_prev_ts(0);
   $obj->set_first_ts(0);

   throws_ok(
      sub { $obj->_calc_deltas() },
      qr/Time between samples should be > 0, is /,
      "$test->{class}, ->_calc_deltas fails if the time elapsed is 0"
   );

   $obj->set_curr_ts(0);
   $obj->set_prev_ts(4);
   $obj->set_first_ts(4);

   throws_ok(
      sub { $obj->_calc_deltas() },
      qr/Time between samples should be > 0, is /,
      "$test->{class}, ->_calc_deltas fails if the time elapsed is negative"
   );
}

# ###########################################################################
# --group-by sample + --devices-regex show the wrong device
# https://bugs.launchpad.net/percona-toolkit/+bug/1035311
# ###########################################################################
my $sample_obj = DiskstatsGroupBySample->new( OptionParser => $o, devices_regex => qr/./ );

$sample_obj->ordered_devs( [ "aaaa", "bbbb" ] );

for (
   [ 1, "aaaa", "with 1 dev shows the first device" ],
   [ 5, "{5}",  'with 5 devs shows "{5}"'],
   [ 2, "{2}",  'with 2 devs shows "{2}"' ],
   [ 1, "bbbb", 'with 1 devs and a filtering devices_regex, shows "bbbb"'],
)
{
   my ($num_devs, $expected, $test) = @$_;
   is(
      $sample_obj->compute_dev($num_devs),
      $expected,
      "DiskstatsGroupBySample->compute_dev $test"
   );

   # After the first iteration, change the 
   $sample_obj->set_devices_regex(qr/^bbbb/);
}

# ###########################################################################
# Done.
# ###########################################################################
done_testing;
exit;
