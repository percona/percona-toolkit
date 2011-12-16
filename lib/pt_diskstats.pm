{
package pt_diskstats;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use DiskstatsMenu;
use OptionParser;

local $SIG{__DIE__} = sub {
   require Carp;
   Carp::confess(@_) unless $^S; # This is $EXCEPTIONS_BEING_CAUGHT
} if MKDEBUG;

sub main {
   shift;
   local @ARGV = @_;  # set global ARGV for this package

   # ########################################################################
   # Get configuration information.
   # ########################################################################
   my $o = OptionParser->new( file => __FILE__ );
   $o->get_specs();
   $o->get_opts();

   # Interactive mode. Delegate to Diskstats::Menu
   return DiskstatsMenu->run_interactive( o => $o, filename => $ARGV[0] );
}

# Somewhat important if STDOUT is tied to a terminal.
END { close STDOUT or die "Couldn't close stdout: $OS_ERROR" }

__PACKAGE__->main(@ARGV) unless caller;

1;
}
=pod

=head1 NAME

pt-diskstats - Aggregate and summarize F</proc/diskstats>.

=head1 SYNOPSIS

Usage: pt-diskstats [OPTION...] [FILES]

pt-diskstats reads F</proc/diskstats> periodically, or files with the
contents of F</proc/diskstats>, aggregates the data, and prints it nicely.

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-diskstats is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.percona.com/bugs/pt-diskstats>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

pt-diskstats tool is similar to iostat, but has some advantages. It separates
reads and writes, for example, and computes some things that iostat does in
either incorrect or confusing ways.  It is also menu-driven and interactive
with several different ways to aggregate the data, and integrates well with
the L<pt-collect> tool. These properties make it very convenient for quickly
drilling down into I/O performance at the desired level of granularity.

This program works in two main modes. One way is to process a file with saved
disk statistics, which you specify on the command line.  The other way is to
start a background process gathering samples at intervals and saving them into
a file, and process this file in the foreground.  In both cases, the tool is
interactively controlled by keystrokes, so you can redisplay and slice the
data flexibly and easily.  If the tool is not attached to a terminal, it
doesn't run interactively; it just processes and prints its output, then exits.
Otherwise it loops until you exit with the 'q' key.

If you press the '?' key, you will bring up the interactive help menu that
shows which keys control the program.

XXX TODO:

Files should have this format:

   <contents of /proc/diskstats>
   TS <timestamp>
   <contents of /proc/diskstats>
   ... et cetera
   TS <timestamp>  <-- must end with a TS line.

See L<http://aspersa.googlecode.com/svn/html/diskstats.html> for a detailed
example of using the tool.

=head1 OUTPUT

The columns are as follows:

=over

=item #ts

The number of seconds of samples in the line.  If there is only one, then
the timestamp itself is shown, without the {curly braces}.

=item device

The device name.  If there is more than one device, then instead the number
of devices aggregated into the line is shown, in {curly braces}.

=item rd_mb_s

The number of megabytes read per second, average, during the sampled interval.

=item rd_cnc

The average concurrency of the read operations, as computed by Little's Law
(a.k.a. queueing theory).

=item rd_rt

The average response time of the read operations, in milliseconds.

=item wr_mb_s

Megabytes written per second, average.

=item wr_cnc

Write concurrency, similar to read concurrency.

=item wr_rt

Write response time, similar to read response time.

=item busy

The fraction of time that the device had at least one request in progress;
this is what iostat calls %util (which is a misleading name).

=item in_prg

The number of requests that were in progress.  Unlike the read and write
concurrencies, which are averages that are generated from reliable numbers,
this number is an instantaneous sample, and you can see that it might
represent a spike of requests, rather than the true long-term average.

=back

In addition to the above columns, there are a few columns that are hidden by
default. If you press the 'c' key, and then press Enter, you will blank out
the regular expression pattern that selects columns to display, and you will
then see the extra columns:

=over

=item rd_s

The number of reads per second.

=item rd_avkb

The average size of the reads, in kilobytes.

=item rd_mrg

The percentage of read requests that were merged together in the disk
scheduler before reaching the device.

=item wr_s, wr_avgkb, and wr_mrg

These are analogous to their C<rd_*> cousins.

=back

=head1 OPTIONS

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --columns

type: string; default: cnc|rt|busy|prg|time|io_s

Perl regex of which columns to include.

=item --devices

type: string

Perl regex of which devices to include.

=item --group-by

type: string; default: disk

Group-by mode (default disk); specify one of the following:

   disk   - Each line of output shows one disk device.
   sample - Each line of output shows one sample of statistics.
   all    - Each line of output shows one sample and one disk device.

=item --sample-time

type: int; default: 1

In --group-by sample mode, include INTERVAL seconds of samples per group.

=item --save-samples

type: string

File to save diskstats samples in; these can be used for later analysis.

=item --iterations

type: int

When in interactive mode, stop after N samples.

=item --interval

type: int; default: 1

Sample /proc/diskstats every N seconds.

=item --help

Show help and exit.

=item --version

Show version and exit.

=back

=head1 ENVIRONMENT

This tool does not use any environment variables.

=head1 SYSTEM REQUIREMENTS

This tool requires Perl v5.8.0 or newer and the F</proc> filesystem, unless
reading from files.

=head1 BUGS

For a list of known bugs, see L<http://www.percona.com/bugs/pt-diskstats>.

Please report bugs at L<https://bugs.launchpad.net/percona-toolkit>.
Include the following information in your bug report:

=over

=item * Complete command-line used to run the tool

=item * Tool L<"--version">

=item * MySQL version of all servers involved

=item * Output from the tool including STDERR

=item * Input files (log/dump/config files, etc.)

=back

If possible, include debugging output by running the tool with C<PTDEBUG>;
see L<"ENVIRONMENT">.

=head1 DOWNLOADING

Visit L<http://www.percona.com/software/percona-toolkit/> to download the
latest release of Percona Toolkit.  Or, get the latest release from the
command line:

   wget percona.com/get/percona-toolkit.tar.gz

   wget percona.com/get/percona-toolkit.rpm

   wget percona.com/get/percona-toolkit.deb

You can also get individual tools from the latest release:

   wget percona.com/get/TOOL

Replace C<TOOL> with the name of any tool.

=head1 AUTHORS

Baron Schwartz

=head1 ABOUT PERCONA TOOLKIT

This tool is part of Percona Toolkit, a collection of advanced command-line
tools developed by Percona for MySQL support and consulting.  Percona Toolkit
was forked from two projects in June, 2011: Maatkit and Aspersa.  Those
projects were created by Baron Schwartz and developed primarily by him and
Daniel Nichter, both of whom are employed by Percona.  Visit
L<http://www.percona.com/software/> for more software developed by Percona.

=head1 COPYRIGHT, LICENSE, AND WARRANTY

This program is copyright 2010-2011 Baron Schwartz, 2011 Percona Inc.
Feedback and improvements are welcome.

THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
systems, you can issue `man perlgpl' or `man perlartistic' to read these
licenses.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place, Suite 330, Boston, MA  02111-1307  USA.

=head1 VERSION

pt-diskstats 2.0.0_WIP

=cut
