#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use IO::File;
use Fcntl      qw(:seek);
use File::Temp qw(tempfile);

use PerconaTest;
require "$trunk/bin/pt-query-digest";

my $samples = "$trunk/t/lib/samples/slowlogs";
my $output;

my $resume_file = (tempfile())[1];
diag(`echo 0 > $resume_file`);

my ($fh, $filename) = tempfile(UNLINK => 1);
$fh->autoflush(1);

sub resume_offset_ok {
   my ($resume_file, $file, $msg) = @_;
   chomp(my $offset = slurp_file($resume_file));
   open my $tmp_fh, q{<}, $file or die $OS_ERROR;
   seek $tmp_fh, 0, SEEK_END;
   is(tell($tmp_fh), $offset, $msg);
}

sub run_pqd {
   my @extra_args = @_;
   my $run = output(sub { pt_query_digest::main(qw(--limit 10), @extra_args, $filename) }, stderr => 1);
   $run =~ s/[\d.]+m?s user time.+//;
   $run =~ s/Current date: .+//;
   return $run;
}

print { $fh } slurp_file("$samples/slow006.txt");

my @runs;
push @runs, run_pqd() for 1, 2;

is(
   $runs[0],
   $runs[1],
   "Sanity check: Behaves the same between runs without --resume"
);

my @resume_runs;
push @resume_runs, run_pqd('--resume', $resume_file) for 1, 2;

# TODO
#(my $without_resume_line = $resume_runs[0]) =~ s/\n\n. Saved resume file offset.+//;
#is(
#   $runs[1],
#   $runs[0],
#   "First time with --resume just like the first time without"
#);

like(
   $resume_runs[0],
   qr/\QSaved resume file offset\E/,
   "Saves offset with --resume"
);

like(
   $resume_runs[1],
   qr/\QNo events processed.\E/,
   "..and there are no events on the second run"
);

resume_offset_ok(
   $resume_file,
   $filename,
   "The resume file has the correct offset"
);

print { $fh } slurp_file("$samples/slow002.txt");

push @resume_runs, run_pqd('--resume', $resume_file) for 1, 2;

unlike(
   $resume_runs[2],
   qr/\QNo events processed.\E/,
   "New run detects new events"
);

like(
   $resume_runs[3],
   qr/\QNo events processed.\E/,
   "And running again after that finds nothing new"
);

resume_offset_ok(
   $resume_file,
   $filename,
   "The resume file has the updated offset"
);

# #############################################################################
# Now test the itneraction with --run-time-mode interval
# #############################################################################

close $fh;
diag(`echo 0 > $resume_file`);

($fh, $filename) = tempfile(UNLINK => 1);
$fh->autoflush(1);

print { $fh } slurp_file("$trunk/t/lib/samples/slowlogs/slow033.txt");

my @run_args = (qw(--run-time-mode interval --run-time 1d --iterations 0),
                qw(--report-format query_report));
my @resume_args = (@run_args, '--resume', $resume_file);

my @run_time;
push @run_time, run_pqd(@resume_args) for 1,2;

resume_offset_ok(
   $resume_file,
   $filename,
   "The resume file has the correct offset when using --run-time-mode interval"
);

print { $fh } slurp_file("$samples/slow002.txt");

push @run_time, run_pqd(@resume_args) for 1,2;

resume_offset_ok(
   $resume_file,
   $filename,
   "...and it updates correctly"
);

like(
   $_,
   qr/\QNo events processed.\E/,
   "Runs 2 & 4 find no new data"
) for @run_time[1, 3];

# This shows up in the first report, but shouldn't show up in there
# third run, after we add new events to the file.
my $re = qr/\QSELECT * FROM foo\E/;

unlike(
   $run_time[2],
   $re,
   "Events from the first run are correctly ignored"
);

my $no_resume = run_pqd(@run_args);

like(
   $no_resume,
   $re,
   "...but do show up if run without resume"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
