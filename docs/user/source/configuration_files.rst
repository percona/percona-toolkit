
*******************
CONFIGURATION FILES
*******************

Percona Toolkit tools can read options from configuration files.  The
configuration file syntax is simple and direct, and bears some resemblances
to the MySQL command-line client tools.  The configuration files all follow
the same conventions.

Internally, what actually happens is that the lines are read from the file and
then added as command-line options and arguments to the tool, so just
think of the configuration files as a way to write your command lines.

SYNTAX
======

The syntax of the configuration files is as follows:

\*
 
 Whitespace followed by a hash (#) sign signifies that the rest of the line is a
 comment.  This is deleted.
 

\*
 
 Whitespace is stripped from the beginning and end of all lines.
 

\*
 
 Empty lines are ignored.
 

\*
 
 Each line is permitted to be in either of the following formats:
 
 
 .. code-block:: perl
 
    option
    option=value
 
 
 Whitespace around the equals sign is deleted during processing.
 

\*
 
 Only long options are recognized.
 

\*
 
 A line containing only two hyphens signals the end of option parsing.  Any
 further lines are interpreted as additional arguments (not options) to the
 program.
 

READ ORDER
==========

The tools read several configuration files in order:

1.
 
 The global Percona Toolkit configuration file,
 \ */etc/percona-toolkit/percona-toolkit.conf*\ .  All tools read this file,
 so you should only add options to it that you want to apply to all tools.
 

2.
 
 The global tool-specific configuration file, \ */etc/percona-toolkit/TOOL.conf*\ ,
 where \ ``TOOL``\  is a tool name like \ ``pt-query-digest``\ .  This file is named
 after the specific tool you're using, so you can add options that apply
 only to that tool.
 

3.
 
 The user's own Percona Toolkit configuration file,
 \ *$HOME/.percona-toolkit.conf*\ .  All tools read this file, so you should only
 add options to it that you want to apply to all tools.
 

4.
 
 The user's tool-specific configuration file, \ *$HOME/.TOOL.conf*\ ,
 where \ ``TOOL``\  is a tool name like \ ``pt-query-digest``\ .  This file is named
 after the specific tool you're using, so you can add options that apply
 only to that tool.
 

SPECIFYING
==========

There is a special \ ``--config``\  option, which lets you specify which
configuration files Percona Toolkit should read.  You specify a
comma-separated list of files.  However, its behavior is not like other
command-line options.  It must be given \ **first**\  on the command line,
before any other options.  If you try to specify it anywhere else, it will
cause an error.  Also, you cannot specify \ ``--config=/path/to/file``\ ;
you must specify the option and the path to the file separated by whitespace
\ *without an equal sign*\  between them, like:

.. code-block:: perl

   --config /path/to/file

If you don't want any configuration files at all, specify \ ``--config ''``\  to
provide an empty list of files.

