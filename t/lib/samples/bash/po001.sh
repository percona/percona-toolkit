#!/usr/bin/env bash

# This is a fake script for testing the parse_options.sh lib.
exit 0;

# ############################################################################
# Documentation
# ############################################################################
:<<'DOCUMENTATION'
=pod

=head1 NAME

pt-stalk - Wait for a condition to occur then begin collecting data.

=head1 SYNOPSIS

Usage: pt-stalk [OPTIONS] [-- MYSQL_OPTIONS]

pt-stalk watches for a condition to become true, and when it does, executes
a script.  By default it executes L<pt-collect>, but that can be customized.
This tool is useful for gathering diagnostic data when an infrequent event
occurs, so an expert person can review the data later.

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-stalk is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.percona.com/bugs/pt-stalk>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

Although pt-stalk comes pre-configured to do a specific thing, in general
this tool is just a skeleton script for the following flow of actions:

=over

=item 1.

Loop infinitely, sleeping between iterations.

=item 2.

In each iteration, run some command and get the output.

=item 3.

If the command fails or the output is larger than the threshold,
execute the collection script; but do not execute if the destination disk
is too full.

=back

By default, the tool is configured to execute mysqladmin extended-status and
extract the value of the Threads_connected variable; if this is greater than
100, it runs the collection script. This is really just placeholder code,
and almost certainly needs to be customized!

If the tool does execute the collection script, it will wait for a while
before checking and executing again.  This is to prevent a continuous
condition from causing a huge number of executions to fire off.

The name 'stalk' is because 'watch' is already taken, and 'stalk' is fun.

=head1 CONFIGURING

If the file F<pt-stalk.conf> exists in the current working directory, then
L<"ENVIRONMENT"> variables are imported from it.  For example, the config
file has the format:

   INTERVAL=10
   GDB=yes

See L<"ENVIRONMENT">.

=head1 OPTIONS

=over

=item --string-opt

type: string

String option without a default.

=item --string-opt2

type: string; default: foo

String option with a default.

=item --typeless-option

Just an option.

=item --noption

default: yes; negatable: yes

Negatable option.

=item --int-opt

type: int

Int option without a default.

=item --int-opt2

type: int; default: 42

Int option with a default.

=item --version

short form: -v

Print tool's version and exit.

=item --help

Print help and exit.

=back

=head1 ENVIRONMENT

The following environment variables configure how, what, and when the tool
runs.  They are all optional and can be specified either on the command line
or in the F<pt-stalk.conf> config file (see L<"CONFIGURING">).

=over

=item THRESHOLD (default 100)

This is the max number of <whatever> we want to tolerate.

=item VARIABLE (default Threads_connected}

This is the thing to check for.

=item CYCLES (default 1)

How many times must the condition be met before the script will fire?

=item GDB (default no)

Collect GDB stacktraces?

=item OPROFILE (default yes)

Collect oprofile data?

=item STRACE (default no)

Collect strace data?

=item TCPDUMP (default yes)

Collect tcpdump data?

=item EMAIL

Send mail to this list of addresses when the script triggers.

=item MYSQLOPTIONS

Any options to pass to mysql/mysqladmin, such as -u, -p, etc

=item INTERVAL (default 30)

This is the interval between checks.

=item MAYBE_EMPTY (default no)

If the command you're running to detect the condition is allowed to return
nothing (e.g. a grep line that might not even exist if there's no problem),
then set this to "yes".

=item COLLECT (default ${HOME}/bin/pt-collect)

This is the location of the 'collect' script.

=item DEST (default ${HOME}/collected/)

This is where to store the collected data.

=item DURATION (default 30)

How long to collect statistics data for?  Make sure that this isn't longer
than SLEEP.

=item SLEEP (default DURATION * 10)

How long to sleep after collecting?

=item PCT_THRESHOLD (default 95)

Bail out if the disk is more than this %full.

=item MB_THRESHOLD (default 100)

Bail out if the disk has less than this many MB free.

=item PURGE (default 30)

Remove samples after this many days.

=back

=head1 SYSTEM REQUIREMENTS

This tool requires Bash v3 or newer.

=head1 BUGS

For a list of known bugs, see L<http://www.percona.com/bugs/pt-stalk>.

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

Baron Schwartz, Justin Swanhart, and Fernando Ipar

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

pt-stalk 1.0.1

=cut

DOCUMENTATION
