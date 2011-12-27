#!/usr/bin/env bash

:

# ############################################################################
# Documentation
# ############################################################################
:<<'DOCUMENTATION'
=pod

=head1 NAME

pt-stalk - Wait for a condition to occur then begin collecting data.

=head1 OPTIONS

=over

=item --collect

default: yes; negatable: yes

Collect system information.

=item --collect-gdb

Collect GDB stacktraces.

=item --collect-oprofile

Collect oprofile data.

=item --collect-strace

Collect strace data.

=item --collect-tcpdump

Collect tcpdump data.

=item --cycles

type: int; default: 5

Number of times condition must be met before triggering collection.

=item --daemonize

default: yes; negatable: yes

Daemonize the tool.

=item --dest

type: string

Where to store collected data.

=item --disk-byte-limit

type: int; default: 100

Exit if the disk has less than this many MB free.

=item --disk-pct-limit

type: int; default: 5

Exit if the disk is less than this %full.

=item --execute-command

type: string; default: pt-collect

Location of the C<pt-collect> tool.

=item --function

type: string; default: status

Built-in function name or plugin file name which returns the value of C<VARIABLE>.

Possible values are:

=over

=item * status

Grep the value of C<VARIABLE> from C<mysqladmin extended-status>.

=item * processlist

Count the number of processes in C<mysqladmin processlist> whose
C<VARIABLE> column matches C<MATCH>.  For example:

   TRIGGER_FUNCTION="processlist" \
   VARIABLE="State"               \
   MATCH="statistics"             \
   THRESHOLD="10"

The above triggers when more than 10 processes are in the "statistics" state.
C<MATCH> must be specified for this trigger function.

=item * magic

TODO

=item * plugin file name

A plugin file allows you to specify a custom trigger function.  The plugin
file must contain a function called C<trg_plugin>.  For example:

   trg_plugin() {
      # Do some stuff.
      echo "$value"
   }

The last output if the function (its "return value") must be a number.
This number is compared to C<THRESHOLD>.  All L<"ENVIRONMENT"> variables
are available to the function.

Do not alter the tool's existing global variables.  Prefix any plugin-specific
global variables with "PLUGIN_".

=back

=item --help

Print help and exit.

=item --interval

type: int; default: 1

Interval between checks.

=item --iterations

type: int

Exit after triggering C<pt-collect> this many times.  By default, the tool
will collect as many times as it's triggered.

=item --log

type: string; default: /var/log/pt-stalk.log

Print all output to this file when daemonized.

=item --match

type: string

Match pattern for C<processles> L<"--function">.

=item --notify-by-email

type: string

Send mail to this list of addresses when C<pt-collect> triggers.

=item --pid FILE

type: string; default: /var/run/pt-stalk.pid

Create a PID file when daemonized.

=item --retention-time

type: int; default: 30

Remove samples after this many days.

=item --run-time

type: int; default: 30

How long to collect statistics data for?

Make sure that this isn't longer than SLEEP.

=item --sleep

type: int; default: 300

How long to sleep after collecting?

=item --threshold N

type: int; default: 25

Max number of C<N> to tolerate.

=item --variable NAME

type: string; default: Threads_running

This is the thing to check for.

=item --version

Print tool's version and exit.

=back

=head1 ENVIRONMENT

No env vars used.

=cut

DOCUMENTATION
