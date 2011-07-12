#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 4;

use SlowLogParser;
use SlowLogWriter;
use PerconaTest;

my $p = new SlowLogParser;
my $w = new SlowLogWriter;

sub __no_diff {
   my ( $filename, $expected ) = @_;

   # Parse and rewrite the original file.
   my $tmp_file = '/tmp/SlowLogWriter-test.txt';
   open my $rewritten_fh, '>', $tmp_file
      or die "Cannot write to $tmp_file: $OS_ERROR";
   open my $fh, "<", "$trunk/$filename"
      or die "Cannot open $trunk/$filename: $OS_ERROR";
   my %args = (
      next_event => sub { return <$fh>;    },
      tell       => sub { return tell $fh; },
   );
   while ( my $e = $p->parse_event(%args) ) {
      $w->write($rewritten_fh, $e);
   }
   close $fh;
   close $rewritten_fh;

   # Compare the contents of the two files.
   my $retval = system("diff $tmp_file $trunk/$expected");
   `rm -rf $tmp_file`;
   $retval = $retval >> 8;
   return !$retval;
}

sub write_event {
   my ( $event, $expected_output ) = @_;
   my $tmp_file = '/tmp/SlowLogWriter-output.txt';
   open my $fh, '>', $tmp_file or die "Cannot open $tmp_file: $OS_ERROR";
   $w->write($fh, $event);
   close $fh;
   my $retval = system("diff $tmp_file $trunk/$expected_output");
   `rm -rf $tmp_file`;
   $retval = $retval >> 8;
   return !$retval;
}

# Check that I can write a slow log in the default slow log format.
ok(
   __no_diff('t/lib/samples/slowlogs/slow001.txt', 't/lib/samples/slowlogs/slow001-rewritten.txt'),
   'slow001.txt rewritten'
);

# Test writing a Percona-patched slow log with Thread_id and hi-res Query_time.
ok(
   __no_diff('t/lib/samples/slowlogs/slow032.txt', 't/lib/samples/slowlogs/slow032-rewritten.txt'),
   'slow032.txt rewritten'
);

ok(
   write_event(
      {
         Query_time => '1',
         arg        => 'select * from foo',
         ip         => '127.0.0.1',
         port       => '12345',
      },
      't/lib/samples/slowlogs/slowlogwriter001.txt',
   ),
   'Writes Client attrib from tcpdump',
);

ok(
   write_event(
      {
         Query_time => '1.123456',
         Lock_time  => '0.000001',
         arg        => 'select * from foo',
      },
      't/lib/samples/slowlogs/slowlogwriter002.txt',
   ),
   'Writes microsecond times'
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -rf SlowLogWriter-test.txt >/dev/null 2>&1`);
exit;
