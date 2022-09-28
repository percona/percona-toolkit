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

  pt-secure-data [<flags>] <command> [<args> ...]

By default, :program:`pt-secure-collect` will collect the output of:

-  ``pt-stalk``
-  ``pt-summary``
-  ``pt-mysql-summary``

Global flags
------------

.. option:: --help

   Show context-sensitive help (also try --help-long and --help-man).

.. option:: --debug

   Enable debug log level.

COMMANDS
========

* **Help command**

  Show help

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

  .. option:: --ask-mysql-pass

     password.

  .. option:: --extra-cmd

     Also run this command as part of the data collection. This parameter can
     be used more than once.

  .. option:: --encrypt-password

     Encrypt the output file using this password. If ommited, it will be asked
     in the command line.

  .. option:: --no-collect

     Do not collect data

  .. option:: --no-sanitize

     Do not sanitize data

  .. option:: --no-encrypt

     Do not encrypt the output file.

  .. option:: --no-sanitize-hostnames

     Do not sanitize hostnames.

  .. option:: --no-sanitize-queries

     Do not replace queries by their fingerprints.

  .. option:: --no-remove-temp-files

     Do not remove temporary files.

* **Decrypt command**

  Decrypt an encrypted file. The password will be requested from the
  terminal. Usage:

  ::

    pt-secure-collect decrypt [flags] <input file>

  .. option:: --outfile

     Write the output to this file. If ommited, the output file
     name will be the same as the input file, adding the ``.aes`` extension.

* **Encrypt command**

  Encrypt a file. The password will be requested from the terminal. Usage:

  ::

    pt-secure-collect encrypt [flags] <input file>

  .. option:: --outfile

     Write the output to this file. If ommited, the output file
     name will be the same as the input file, without the ``.aes`` extension.

* **Sanitize command**

  Replace queries in a file by their fingerprints and obfuscate hostnames.
  Usage:

  ::

    pt-secure-collect sanitize [flags]

  .. option:: --input-file

     Input file. If not specified, the input will  be Stdin.

  .. option:: --output-file

     Output file. If not specified, the input will be Stdout.

  .. option:: --no-sanitize-hostnames

     Do not sanitize host names.

  .. option:: --no-sanitize-queries

     Do not replace queries by their fingerprints.
