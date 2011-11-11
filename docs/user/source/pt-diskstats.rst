.. program:: pt-diskstats

=========================
 :program:`pt-diskstats`
=========================

.. highlight:: perl


NAME
====

:program:`pt-diskstats` - Aggregate and summarize \ */proc/diskstats*\ .


SYNOPSIS
========

Usage
-----

::

  pt-diskstats [OPTIONS] [FILES]

:program:`pt-diskstats` reads \ */proc/diskstats*\  periodically, or files with the contents of \ */proc/diskstats*\ , aggregates the data, and prints it nicely.

RISKS
=====

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-diskstats` is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-diskstats <http://www.percona.com/bugs/pt-diskstats>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-diskstats` tool is similar to iostat, but has some advantages. It separates reads and writes, for example, and computes some things that iostat does in either incorrect or confusing ways.  It is also menu-driven and interactive with several different ways to aggregate the data, and integrates well with the :program:`pt-collect` tool. These properties make it very convenient for quickly drilling down into I/O performance at the desired level of granularity.

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

Files should have this format:

.. code-block:: perl

    <contents of /proc/diskstats>
    TS <timestamp>
    <contents of /proc/diskstats>
    ... et cetera
    TS <timestamp>  <-- must end with a TS line.

See `http://aspersa.googlecode.com/svn/html/diskstats.html <http://aspersa.googlecode.com/svn/html/diskstats.html>`_ for a detailed
example of using the tool.

OUTPUT
======


The columns are as follows:

  * ``#ts``
 
 The number of seconds of samples in the line.  If there is only one, then
 the timestamp itself is shown, without the {curly braces}.
 
  * ``device``
 
 The device name.  If there is more than one device, then instead the number
 of devices aggregated into the line is shown, in {curly braces}.
 
  * ``rd_mb_s``
 
 The number of megabytes read per second, average, during the sampled interval.
 
  * ``rd_cnc``
 
 The average concurrency of the read operations, as computed by Little's Law
 (a.k.a. queueing theory).
 
  * ``rd_rt``
 
 The average response time of the read operations, in milliseconds.
 
  * ``wr_mb_s``
 
 Megabytes written per second, average.
 
  * ``wr_cnc``
 
 Write concurrency, similar to read concurrency.
 
  * ``wr_rt``
 
 Write response time, similar to read response time.
 
  * ``busy``
 
 The fraction of time that the device had at least one request in progress;
 this is what iostat calls %util (which is a misleading name).
 
  * ``in_prg``
 
 The number of requests that were in progress.  Unlike the read and write
 concurrencies, which are averages that are generated from reliable numbers,
 this number is an instantaneous sample, and you can see that it might
 represent a spike of requests, rather than the true long-term average.
 

In addition to the above columns, there are a few columns that are hidden by
default. If you press the 'c' key, and then press Enter, you will blank out
the regular expression pattern that selects columns to display, and you will
then see the extra columns:

  * ``rd_s``
 
 The number of reads per second.
 
  * ``rd_avkb``
 
 The average size of the reads, in kilobytes.
 
  * ``rd_mrg``
 
 The percentage of read requests that were merged together in the disk
 scheduler before reaching the device.
 
  * ``wr_s``, ``wr_avgkb``, and ``wr_mrg``
 
 These are analogous to their \ ``rd_\*``\  cousins.
 

OPTIONS
=======

Options must precede files on the command line.

.. option:: -c COLS
 
 Awk regex of which columns to include (default ``cnc|rt|mb|busy|prg``).
 
.. option:: -d DEVICES
 
 Awk regex of which devices to include.
 
.. option:: -g GROUPBY
 
 Group-by mode (default disk); specify one of the following:
 
  .. code-block:: perl
 
     disk   - Each line of output shows one disk device.
     sample - Each line of output shows one sample of statistics.
     all    - Each line of output shows one sample and one disk device.
 
 .. option:: -i INTERVAL
 
 In -g sample mode, include INTERVAL seconds per sample.
 
.. option:: -k KEEPFILE
 
 File to save diskstats samples in (default /tmp/diskstats-samples).
 If a non-default filename is used, it will be saved for later analysis.
 
.. option:: -n SAMPLES
 
 When in interactive mode, stop after N samples.
 
.. option:: -s INTERVAL
 
 Sample /proc/diskstats every N seconds (default 1).
 

ENVIRONMENT
===========

This tool does not use any environment variables.

SYSTEM REQUIREMENTS
===================

This tool requires Bash v3 or newer and the \ */proc*\  filesystem unless
reading from files.

BUGS
====

For a list of known bugs, see `http://www.percona.com/bugs/pt-diskstats <http://www.percona.com/bugs/pt-diskstats>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.

AUTHORS
=======

Baron Schwartz

COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2010-2011 Baron Schwartz, 2011 Percona Inc.
Feedback and improvements are welcome.

VERSION
=======

:program:`pt-diskstats` 1.0.1

