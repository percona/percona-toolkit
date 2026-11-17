#!/usr/bin/env perl

# --retention-count, --retention-size and --retention-time.  Uses the fake
# commands; no MongoDB server.

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib",
                 "$ENV{PERCONA_TOOLKIT_BRANCH}/t/pt-mongodb-stalk/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use File::Path qw(make_path);
use Test::More;

use PerconaTest;
use PtMongodbStalkTest;

use_fake_commands();

my ($status, $output);

# Write a file of $size bytes, modified $days_ago days ago.
sub old_file {
   my ($file, $days_ago, $size) = @_;
   open my $fh, ">", $file or die "Cannot write $file: $OS_ERROR";
   print {$fh} "x" x ($size || 10);
   close $fh;
   my $time = time - $days_ago * 86400;
   utime($time, $time, $file) or die "Cannot set the time of $file: $OS_ERROR";
   return;
}

# A previous collection: its trigger file and one data file.
sub old_collection {
   my ($dir, $prefix, $days_ago, $size) = @_;
   old_file("$dir/$prefix-trigger", $days_ago);
   old_file("$dir/$prefix-serverstatus", $days_ago, $size);
   return;
}

sub run_in {
   my ($dir, @args) = @_;
   return run_capture(
      "bash", $tool, @common_args,
      "--sleep", "1",
      "--dest", $dir,
      "--pid", "$dir/pt-mongodb-stalk.pid",
      @args,
   );
}

# ###########################################################################
# --retention-count: only the newest N collections are kept, and files that
# are not collections (here the PID file, while the tool runs) are left alone.
# ###########################################################################

my $dest = "$tmpdir/retention-count";
($status, $output) = run_in($dest, "--iterations", "4", "--retention-count", "2");
is($status, 0, "--retention-count collection exits 0") or diag($output);
my @kept = grep { $_ ne 'pt' } prefixes_in($dest);
is(scalar @kept, 2, "--retention-count 2 keeps 2 collections")
   or diag(join("\n", glob("$dest/*")));
ok(-f "$dest/$kept[$_]-serverstatus", "kept collection $_ is complete") for 0..$#kept;

# ###########################################################################
# --retention-size: the oldest collections are deleted until --dest is at most
# that many MB, but the newest one is always kept.
# ###########################################################################

$dest = "$tmpdir/retention-size";
make_path($dest);
old_collection($dest, "2026_01_01_00_00_00", 1, 2 * 1024 * 1024);
old_collection($dest, "2026_01_02_00_00_00", 1, 2 * 1024 * 1024);
old_file("$dest/notes.txt", 1);
($status, $output) = run_in($dest, "--iterations", "1", "--retention-size", "1");
is($status, 0, "--retention-size collection exits 0") or diag($output);
my @prefixes = prefixes_in($dest);
is(scalar @prefixes, 1, "--retention-size 1 deletes the 2 MB collections")
   or diag(join("\n", glob("$dest/*")));
unlike($prefixes[0] || '', qr/^2026_01_0[12]/, "the newest collection is kept");
ok(-f "$dest/notes.txt", "files that are not collections are kept");

$dest = "$tmpdir/retention-size-newest";
make_path($dest);
($status, $output) = run_in($dest, "--iterations", "1", "--retention-size", "1",
   "--prefix", "BIG");
old_file("$dest/BIG-serverstatus", 0, 3 * 1024 * 1024);
($status, $output) = run_in($dest, "--iterations", "1", "--retention-size", "1",
   "--prefix", "BIG");
ok(-f "$dest/BIG-trigger", "the newest collection is kept even if bigger than --retention-size");

# ###########################################################################
# --retention-time: files of collections older than N days are deleted.
# ###########################################################################

$dest = "$tmpdir/retention-time";
make_path($dest);
old_collection($dest, "2025_01_01_00_00_00", 40);
old_collection($dest, "2026_10_30_00_00_00", 10);
old_file("$dest/notes.txt", 40);
($status, $output) = run_in($dest, "--iterations", "1", "--retention-time", "30");
is($status, 0, "--retention-time collection exits 0") or diag($output);
ok(!-e "$dest/2025_01_01_00_00_00-trigger", "--retention-time 30 deletes a 40-day-old collection");
ok(-f "$dest/2026_10_30_00_00_00-trigger",  "--retention-time 30 keeps a 10-day-old collection");
ok(-f "$dest/notes.txt", "--retention-time keeps old files that are not collections");

# With --prefix, only the files with that prefix are deleted, as in pt-stalk.
# The files the new collection appends to are recent again, so use a file it
# does not write.
$dest = "$tmpdir/retention-time-prefix";
make_path($dest);
old_file("$dest/MYPREFIX-stacktrace", 40);
old_collection($dest, "2025_01_01_00_00_00", 40);
($status, $output) = run_in($dest, "--iterations", "1", "--retention-time", "30",
   "--prefix", "MYPREFIX");
is($status, 0, "--retention-time with --prefix exits 0") or diag($output);
ok(-f "$dest/MYPREFIX-trigger", "the new collection with --prefix is kept");
ok(!-e "$dest/MYPREFIX-stacktrace", "an old file with the prefix is deleted");
ok(-f "$dest/2025_01_01_00_00_00-trigger",
   "old collections without the prefix are kept when --prefix is given");

done_testing;
