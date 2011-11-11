.. program:: pt-tcp-model

=========================
 :program:`pt-tcp-model`
=========================

.. highlight:: perl


NAME
====

 :program:`pt-tcp-model` - Transform tcpdump into metrics that permit performance and scalability modeling.


SYNOPSIS
========


Usage
-----

::

   pt-tcp-model [OPTION...] [FILE]

:program:`pt-tcp-model` parses and analyzes tcpdump files.  With no FILE, or when
FILE is -, it read standard input.

Dump TCP requests and responses to a file, capturing only the packet headers to
avoid dropped packets, and ignoring any packets without a payload (such as
ack-only packets).  Capture port 3306 (|MySQL| database traffic).  Note that to
avoid line breaking in terminals and man pages, the TCP filtering expression
that follows has a line break at the end of the second line; you should omit
this from your tcpdump command.


.. code-block:: perl

  tcpdump -s 384 -i any -nnq -tttt \
 	'tcp port 3306 and (((ip[2:2] - ((ip[0]&0xf)<<2)) 
       - ((tcp[12]&0xf0)>>2)) != 0)' \
    > /path/to/tcp-file.txt


Extract individual response times, sorted by end time:


.. code-block:: perl

  pt-tcp-model /path/to/tcp-file.txt > requests.txt


Sort the result by arrival time, for input to the next step:


.. code-block:: perl

  sort -n -k1,1 requests.txt > sorted.txt


Slice the result into 10-second intervals and emit throughput, concurrency, and
response time metrics for each interval:


.. code-block:: perl

  pt-tcp-model --type=requests --run-time=10 sorted.txt > sliced.txt


Transform the result for modeling with Aspersa's usl tool, discarding the first
and last line of each file if you specify multiple files (the first and last
line are normally incomplete observation periods and are aberrant):


.. code-block:: perl

  for f in sliced.txt; do
     tail -n +2 "$f" | head -n -1 | awk '{print $2, $3, $7/$4}'
  done > usl-input.txt



RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-tcp-model` merely reads and transforms its input, printing it to the output.
It should be very low risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-tcp-model <http://www.percona.com/bugs/pt-tcp-model>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========


This tool recognizes requests and responses in a TCP stream, and extracts the
"conversations".  You can use it to capture the response times of individual
queries to a database, for example.  It expects the TCP input to be in the
following format, which should result from the sample shown in the SYNOPSIS:


.. code-block:: perl

  <date> <time.microseconds> IP <IP.port> > <IP.port>: <junk>


The tool watches for "incoming" packets to the port you specify with the
:option:`--watch-server` option.  This begins a request.  If multiple inbound packets
follow each other, then by default the last inbound packet seen determines the
time at which the request is assumed to begin.  This is logical if one assumes
that a server must receive the whole SQL statement before beginning execution,
for example.

When the first outbound packet is seen, the server is considered to have
responded to the request.  The tool might see an inbound packet, but never see a
response.  This can happen when the kernel drops packets, for example.  As a
result, the tool never prints a request unless it sees the response to it.
However, the tool actually does not print any request until it sees the "last"
outbound packet.  It determines this by waiting for either another inbound
packet, or EOF, and then considers the previous inbound/outbound pair to be
complete.  As a result, the tool prints requests in a relatively random order.
Most types of analysis require processing in either arrival or completion order.
Therefore, the second type of processing this tool can do requires that you sort
the output from the first stage and supply it as input.

The second type of processing is selected with the :option:`--type` option set to
"requests".  In this mode, the tool reads a group of requests and aggregates
them, then emits the aggregated metrics.


OUTPUT
======


In the default mode (parsing tcpdump output), requests are printed out one per
line, in the following format:


.. code-block:: perl

  <id> <start> <end> <elapsed> <IP:port>


The ID is an incrementing number, assigned in arrival order in the original TCP
traffic.  The start and end timestamps, and the elapsed time, can be customized
with the :option:`--start-end` option.

In :option:`--type=requests` mode, the tool prints out one line per time interval as
defined by :option:`--run-time`, with the following columns: ts, concurrency,
throughput, arrivals, completions, busy_time, weighted_time, sum_time,
variance_mean, quantile_time, obs_time.  A detailed explanation follows:


  * ``ts``
 
 The timestamp that defines the beginning of the interval.
 


  * ``concurrency``
 
 The average number of requests resident in the server during the interval.
 


  * ``throughput``
 
 The number of arrivals per second during the interval.
 


  * ``arrivals``
 
 The number of arrivals during the interval.
 


  * ``completions``
 
 The number of completions during the interval.
 


  * ``busy_time``
 
 The total amount of time during which at least one request was resident in
 the server during the interval.
 


  * ``weighted_time``
 
 The total response time of all the requests resident in the server during the
 interval, including requests that neither arrived nor completed during the
 interval.
 


  * ``sum_time``
 
 The total response time of all the requests that arrived in the interval.
 


  * ``variance_mean``
 
 The variance-to-mean ratio (index of dispersion) of the response times of the
 requests that arrived in the interval.
 


  * ``quantile_time``
 
 The Nth percentile response time for all the requests that arrived in the
 interval.  See also :option:`--quantile`.
 


  * ``obs_time``
 
 The length of the observation time window.  This will usually be the same as the
 interval length, except for the first and last intervals in a file, which might
 have a shorter observation time.
 



OPTIONS
=======


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


.. option:: --config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


.. option:: --help
 
 Show help and exit.
 


.. option:: --progress
 
 type: array; default: time,30
 
 Print progress reports to ``STDERR``.  The value is a comma-separated list with two
 parts.  The first part can be percentage, time, or iterations; the second part
 specifies how often an update should be printed, in percentage, seconds, or
 number of iterations.
 


.. option:: --quantile
 
 type: float
 
 The percentile for the last column when :option:`--type" is "requests` (default .99).
 


.. option:: --run-time
 
 type: float
 
 The size of the aggregation interval in seconds when :option:`--type" is "requests`
 (default 1).  Fractional values are permitted.
 


.. option:: --start-end
 
 type: Array; default: ts,end
 
 Define how the arrival and completion timestamps of a query, and thus its
 response time (elapsed time) are computed.  Recall that there may be multiple
 inbound and outbound packets per request and response, and refer to the
 following ASCII diagram.  Suppose that a client sends a series of three inbound
 (I) packets to the server, whch computes the result and then sends two outbound
 (O) packets back:
 
 
 .. code-block:: perl
 
    I I    I ..................... O    O
    |<---->|<---response time----->|<-->|
    ts0    ts                      end  end1
 
 
 By default, the query is considered to arrive at time ts, and complete at time
 end.  However, this might not be what you want.  Perhaps you do not want to
 consider the query to have completed until time end1.  You can accomplish this
 by setting this option to \ ``ts,end1``\ .
 


.. option:: --type
 
 type: string
 
 The type of input to parse (default tcpdump).  The permitted types are
 
 
  * `` tcpdump``
  
  The parser expects the input to be formatted with the following options: \ ``-x -n
  -q -tttt``\ .  For example, if you want to capture output from your local machine,
  you can do something like the following (the port must come last on FreeBSD):
  
  
  .. code-block:: perl
  
     tcpdump -s 65535 -x -nn -q -tttt -i any -c 1000 port 3306 \
       > mysql.tcp.txt
     pt-query-digest --type tcpdump mysql.tcp.txt
  
  
  The other tcpdump parameters, such as -s, -c, and -i, are up to you.  Just make
  sure the output looks like this (there is a line break in the first line to
  avoid man-page problems):
  
  
  .. code-block:: perl
  
     2009-04-12 09:50:16.804849 IP 127.0.0.1.42167
            > 127.0.0.1.3306: tcp 37
  
  
  All |MySQL| servers running on port 3306 are automatically detected in the
  tcpdump output.  Therefore, if the tcpdump out contains packets from
  multiple servers on port 3306 (for example, 10.0.0.1:3306, 10.0.0.2:3306,
  etc.), all packets/queries from all these servers will be analyzed
  together as if they were one server.
  
  If you're analyzing traffic for a protocol that is not running on port
  3306, see :option:`--watch-server`.
  
 
 


.. option:: --version
 
 Show version and exit.
 


.. option:: --watch-server
 
 type: string; default: 10.10.10.10:3306
 
 This option tells :program:`pt-tcp-model` which server IP address and port (such as
 "10.0.0.1:3306") to watch when parsing tcpdump for :option:`--type` tcpdump.  If you
 don't specify it, the tool watches all servers by looking for any IP address
 using port 3306.  If you're watching a server with a non-standard port, this
 won't work, so you must specify the IP address and port to watch.
 
 Currently, IP address filtering isn't implemented; so even though you must
 specify the option in IP:port form, it ignores the IP and only looks at the port
 number.
 



ENVIRONMENT
===========


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to ``STDERR``.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 :program:`pt-tcp-model` ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


SYSTEM REQUIREMENTS
===================


You need *Perl* , ``DBI``, ``DBD::mysql``, and some core packages that ought to be
installed in any reasonably new version of *Perl* .


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-tcp-model <http://www.percona.com/bugs/pt-tcp-model>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.

AUTHORS
=======

*Baron Schwartz*


COPYRIGHT, LICENSE, AND WARRANTY
================================


This program is copyright 2011 *Baron Schwartz*, 2011 Percona Inc.
Feedback and improvements are welcome.


VERSION
=======

:program:`pt-tcp-model` 1.0.1

