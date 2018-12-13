.. program:: pt-secure-collect

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

Internal variables placeholders will be replaced with the corresponding
flag values. For example, ``$mysql-host`` will be replaced with the
values specified in the ``--mysql-host`` flag.

Global flags
------------

+---------+-------------------------------------------------------------------+
| Flag    | Description                                                       |
+---------+-------------------------------------------------------------------+
| --help  | Show context-sensitive help (also try --help-long and --help-man).|
+---------+-------------------------------------------------------------------+
| --debug | Enable debug log level.                                           |
+---------+-------------------------------------------------------------------+

COMMANDS
========

* **Help command**

  Show help

* **Collect command**

  Collect, sanitize, pack and encrypt data from pt-tools. Usage:

  ::

    pt-secure-collect collect <flags>

  +------------------------+--------------------------------------------------+
  | Flag                   | Description                                      |
  +------------------------+--------------------------------------------------+
  | --bin-dir              | Directory having the Percona Toolkit binaries    |
  |                        | (if they are not in PATH).                       |
  +------------------------+--------------------------------------------------+
  | --temp-dir             | Temporary directory used for the data collection.|
  |                        | Default: ${HOME}/data\_collection\_{timestamp}   |
  +------------------------+--------------------------------------------------+
  | --include-dir          | Include this dir into the sanitized tar file     |
  +------------------------+--------------------------------------------------+
  | --config-file          | Path to the config file.                         |
  |                        | Default: ``~/.my.cnf``                           |
  +------------------------+--------------------------------------------------+
  | --mysql-host           | MySQL host.                                      |
  |                        | Default: ``127.0.0.1``                           |
  +------------------------+--------------------------------------------------+
  | --mysql-port           | MySQL port.                                      |
  |                        | Default: ``3306``                                |
  +------------------------+--------------------------------------------------+
  | --mysql-user           | MySQL user name.                                 |
  +------------------------+--------------------------------------------------+
  | --mysql-password       | MySQL password.                                  |
  +------------------------+--------------------------------------------------+
  | --ask-mysql-pass       | password.                                        |
  +------------------------+--------------------------------------------------+
  | --extra-cmd            | Also run this command as part of the data        |
  |                        | collection. This parameter can be used more than |
  |                        | once.                                            |
  +------------------------+--------------------------------------------------+
  | --encrypt-password     | Encrypt the output file using this password. If  |
  |                        | ommited, it will be asked in the command line.   |
  +------------------------+--------------------------------------------------+
  | --no-collect           | Do not collect data                              |
  +------------------------+--------------------------------------------------+
  | --no-sanitize          | Do not sanitize data                             |
  +------------------------+--------------------------------------------------+
  | --no-encrypt           | Do not encrypt the output file.                  |
  +------------------------+--------------------------------------------------+
  | --no-sanitize-hostnames| Do not sanitize hostnames.                       |
  +------------------------+--------------------------------------------------+
  | --no-sanitize-queries  | Do not replace queries by their fingerprints.    |
  +------------------------+--------------------------------------------------+
  | --no-remove-temp-files | Do not remove temporary files.                   |
  +------------------------+--------------------------------------------------+

* **Decrypt command**

  Decrypt an encrypted file. The password will be requested from the
  terminal. Usage:

  ::

    pt-secure-collect decrypt [flags] <input file>

  +-----------+---------------------------------------------------------------+
  | Flag      | Description                                                   |
  +------------------------+--------------------------------------------------+
  | --outfile | Write the output to this file. If ommited, the output file    |
  |           | name will be the same as the input file, adding the ``.aes``  |
  |           | extension                                                     |
  +-----------+---------------------------------------------------------------+

* **Encrypt command**

  Encrypt a file. The password will be requested from the terminal. Usage:

  ::

    pt-secure-collect encrypt [flags] <input file>

  +-----------+---------------------------------------------------------------+
  | Flag      | Description                                                   |
  +------------------------+--------------------------------------------------+
  | --outfile | Write the output to this file. If ommited, the output file    |
  |           | name will be the same as the input file, without the ``.aes`` |
  |           | extension                                                     |
  +-----------+---------------------------------------------------------------+

* **Sanitize command**

  Replace queries in a file by their fingerprints and obfuscate hostnames.
  Usage:

  ::

    pt-secure-collect sanitize [flags]

  +---------------------------+-----------------------------------------------+
  | Flag                      | Description                                   |
  +------------------------+--------------------------------------------------+
  | --input-file              | Input file. If not specified, the input will  |
  |                           | be Stdin.                                     |
  +---------------------------+-----------------------------------------------+
  | --output-file             | Output file. If not specified, the input will |
  |                           | be Stdout.                                    |
  +---------------------------+-----------------------------------------------+
  | --no-sanitize-hostnames   | Do not sanitize host names.                   |
  +---------------------------+-----------------------------------------------+
  | --no-sanitize-queries     | Do not replace queries by their fingerprints. |
  +---------------------------+-----------------------------------------------+
