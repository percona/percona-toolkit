.. program:: pt-summary

=======================
 :program:`pt-summary`
=======================

.. highlight:: perl


NAME
====

 :program:`pt-summary` - Summarize system information in a nice way.


SYNOPSIS
========


Usage
-----

::

   pt-summary

:program:`pt-summary` conveniently summarizes the status and configuration of a server.
It is not a tuning tool or diagnosis tool.  It produces a report that is easy
to diff and can be pasted into emails without losing the formatting.  This
tool works well on Linux systems.

Download and run:


.. code-block:: perl

    wget http://percona.com/get/pt-summary
    bash ./pt-summary


Download and run in a single step:


.. code-block:: perl

    wget -O- http://percona.com/get/summary | bash



RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-summary` is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-summary <http://www.percona.com/bugs/pt-summary>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-summary` runs a large variety of commands to inspect system status and
configuration, saves the output into files in /tmp, and then runs Unix
commands on these results to format them nicely.  It works best when
executed as a privileged user, but will also work without privileges,
although some output might not be possible to generate without root.


OPTIONS
=======


This tool does not have any command-line options.


ENVIRONMENT
===========


The ``PT_SUMMARY_SKIP`` environment variable specifies a comma-separated list
of things to skip:


.. code-block:: perl

   MOUNT:   Don't print out mounted filesystems and disk fullness.
   NETWORK: Don't print out information on network controllers & config.
   PROCESS: Don't print out top processes and vmstat information.



SYSTEM REQUIREMENTS
===================


This tool requires the Bourne shell (\ */bin/sh*\ ).


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-summary <http://www.percona.com/bugs/pt-summary>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.

AUTHORS
=======

*Baron Schwartz* and *Kevin van Zonneveld* (http://kevin.vanzonneveld.net)


COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2010-2011 *Baron Schwartz*, 2011 Percona Inc.
Feedback and improvements are welcome.

VERSION
=======

:program:`pt-summary` 1.0.1

