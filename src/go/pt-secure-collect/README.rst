============================
:program:`pt-secure-collect`
============================

NAME
====

:program:`pt-secure-collect` - collect, sanitize, pack and encrypt data.

SYNOPSIS
========

Usage
-----

::

  pt-secure-collect [<flags>] <command> [<args> ...]

By default, :program:`pt-secure-collect` will collect the output of:

-  ``pt-stalk  --no-stalk --iterations=2 --sleep=30``
-  ``pt-summary``
-  ``pt-mysql-summary``

Global flags
------------

.. option:: --config

   List of Percona Toolkit configuration file(s) separated by a comma without an equal sign. Must be a first flag. Uses default config file locations if not specified.

.. option:: --help

   Show help and exit.

.. option:: --debug

   Enable debug log level.

.. option:: --version

   Show version and exit.

.. option:: --version-check

   Check for updates (enabled by default).

.. option:: --no-version-check

   Disable update checks.
   

COMMANDS
========

* **Collect command**

  Collect, sanitize, pack and encrypt data from pt-tools. Usage:

  ::

    pt-secure-collect collect <flags>

  .. option:: --bin-dir

     Directory having the Percona Toolkit binaries (if they are not in PATH).

  .. option::  --temp-dir

     Temporary directory used for the data collection.
     Default: ``${HOME}/data_collection_{timestamp}``

  .. option::  --include-dir

     Include this dir into the sanitized tar file.

  .. option:: --config-file

     Path to the config file. Default: ``~/.my.cnf``

  .. option:: --mysql-host

     MySQL host. Default: ``127.0.0.1``

  .. option:: --mysql-port

     MySQL port. Default: ``3306``

  .. option:: --mysql-user

     MySQL user name.

  .. option:: --mysql-password

     MySQL password.

  .. option:: --extra-cmd

     Also run this command as part of the data collection. This parameter can
     be used more than once.

  .. option:: --encrypt-password

     Encrypt the output file using this password. If omitted, it will be asked
     in the command line.

  .. option:: --collect / --no-collect

     Enable or disable archive encryption stage.

  .. option:: --sanitize / --no-sanitize

     Enable or disable sanitization stage.

  .. option:: --encrypt / --no-encrypt

     Enable or disable hostname sanitization.

  .. option:: --sanitize-hostnames / --no-sanitize-hostnames

     Enable or disable query fingerprint sanitization.

  .. option:: --sanitize-queries / --no-sanitize-queries

     Enable or disable command data collection.

  .. option:: --remove-temp-files / --no-remove-temp-files

     Keep or remove temporary files.

* **Decrypt command**

  Decrypt an encrypted file. The password will be requested from the
  terminal. Usage:

  ::

    pt-secure-collect decrypt --infile=<encrypted-file> [flags]

  .. option:: --infile

     Encrypted input file (required).

  .. option:: --outfile

     Write the output to this file. If omitted, the output file
     name is inferred from input file by removing ``.aes`` extension.

  .. option:: --encrypt-password

     Password used for decryption. If omitted, it will be requested interactively.

* **Encrypt command**

  Encrypt a file. The password will be requested from the terminal. Usage:

  ::

    pt-secure-collect encrypt --infile=<plain-file> [flags]

  .. option:: --infile

     Unencrypted input file (required).

  .. option:: --outfile

     Write the output to this file. If omitted, the output file
     name will be the same as the input file, adding the ``.aes`` extension.

  .. option:: --encrypt-password

     Password used for encryption. If omitted, it will be requested interactively.

* **Sanitize command**

  Replace queries in a file by their fingerprints and obfuscate hostnames.
  Usage:

  ::

    pt-secure-collect sanitize [flags]

  .. option:: --input-file

     Input file. If not specified, the input will  be Stdin.

  .. option:: --output-file

     Output file. If not specified, the input will be Stdout.

  .. option:: --sanitize-hostnames / --no-sanitize-hostnames

     Enable or disable hostname sanitization.

  .. option:: --sanitize-queries / --no-sanitize-queries

     Enable or disable query fingerprint sanitization.

Authors
=======

Carlos Salguero

ABOUT PERCONA TOOLKIT
=====================

This tool is part of Percona Toolkit, a collection of advanced command-line
tools for MySQL developed by Percona.  Percona Toolkit was forked from two
projects in June, 2011: Maatkit and Aspersa.  Those projects were created by
Baron Schwartz and primarily developed by him and Daniel Nichter.  Visit
`http://www.percona.com/software/ <http://www.percona.com/software/>`_ to learn about other free, open-source
software from Percona.

COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2011-2026 Percona LLC and/or its affiliates.

THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
systems, you can issue \`man perlgpl' or \`man perlartistic' to read these
licenses.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place, Suite 330, Boston, MA  02111-1307  USA.

VERSION
=======

:program:`pt-secure-collect` 3.7.1
