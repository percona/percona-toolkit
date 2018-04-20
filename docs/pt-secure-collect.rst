pt-secure-collect
=================

Collect, sanitize, pack and encrypt data. By default, this program will
collect the output of:

-  ``pt-stalk --no-stalk --iterations=2 --sleep=30 --host=$mysql-host --dest=$temp-dir --port=$mysql-port --user=$mysql-user --password=$mysql-pass``
-  ``pt-summary``
-  ``pt-mysql-summary --host=$mysql-host --port=$mysql-port --user=$mysql-user --password=$mysql-pass``

Internal variables placeholders will be replaced with the corresponding
flag values. For example, ``$mysql-host`` will be replaced with the
values specified in the ``--mysql-host`` flag.

Usage:

::

    pt-secure-data [<flags>] <command> [<args> ...]

Global flags
~~~~~~~~~~~~

+-----------+----------------------------------------------------------------------+
| Flag      | Description                                                          |
+===========+======================================================================+
| --help    | Show context-sensitive help (also try --help-long and --help-man).   |
+-----------+----------------------------------------------------------------------+
| --debug   | Enable debug log level.                                              |
+-----------+----------------------------------------------------------------------+

**Commands**
~~~~~~~~~~~~

**Help command**
^^^^^^^^^^^^^^^^

Show help

**Collect command**
^^^^^^^^^^^^^^^^^^^

Collect, sanitize, pack and encrypt data from pt-tools. Usage:

::

    pt-secure-collect collect <flags>

+--------+--------+
| Flag   | Descri |
|        | ption  |
+========+========+
| --bin- | Direct |
| dir    | ory    |
|        | having |
|        | the    |
|        | Percon |
|        | a      |
|        | Toolki |
|        | t      |
|        | binari |
|        | es     |
|        | (if    |
|        | they   |
|        | are    |
|        | not in |
|        | PATH). |
+--------+--------+
| --temp | Tempor |
| -dir   | ary    |
|        | direct |
|        | ory    |
|        | used   |
|        | for    |
|        | the    |
|        | data   |
|        | collec |
|        | tion.  |
|        | Defaul |
|        | t:     |
|        | ${HOME |
|        | }/data |
|        | \_coll |
|        | ection |
|        | \_{tim |
|        | estamp |
|        | }      |
+--------+--------+
| --incl | Includ |
| ude-di | e      |
| r      | this   |
|        | dir    |
|        | into   |
|        | the    |
|        | saniti |
|        | zed    |
|        | tar    |
|        | file   |
+--------+--------+
| --conf | Path   |
| ig-fil | to the |
| e      | config |
|        | file.  |
|        | Defaul |
|        | t:     |
|        | ``~/.m |
|        | y.cnf` |
|        | `      |
+--------+--------+
| --mysq | MySQL  |
| l-host | host.  |
|        | Defaul |
|        | t:     |
|        | ``127. |
|        | 0.0.1` |
|        | `      |
+--------+--------+
| --mysq | MySQL  |
| l-port | port.  |
|        | Defaul |
|        | t:     |
|        | ``3306 |
|        | ``     |
+--------+--------+
| --mysq | MySQL  |
| l-user | user   |
|        | name.  |
+--------+--------+
| --mysq | MySQL  |
| l-pass | passwo |
| word   | rd.    |
+--------+--------+
| --ask- | Ask    |
| mysql- | MySQL  |
| pass   | passwo |
|        | rd.    |
+--------+--------+
| --extr | Also   |
| a-cmd  | run    |
|        | this   |
|        | comman |
|        | d      |
|        | as     |
|        | part   |
|        | of the |
|        | data   |
|        | collec |
|        | tion.  |
|        | This   |
|        | parame |
|        | ter    |
|        | can be |
|        | used   |
|        | more   |
|        | than   |
|        | once.  |
+--------+--------+
| --encr | Encryp |
| ypt-pa | t      |
| ssword | the    |
|        | output |
|        | file   |
|        | using  |
|        | this   |
|        | passwo |
|        | rd.If  |
|        | ommite |
|        | d,     |
|        | it     |
|        | will   |
|        | be     |
|        | asked  |
|        | in the |
|        | comman |
|        | d      |
|        | line.  |
+--------+--------+
| --no-c | Do not |
| ollect | collec |
|        | t      |
|        | data   |
+--------+--------+
| --no-s | Do not |
| anitiz | saniti |
| e      | ze     |
|        | data   |
+--------+--------+
| --no-e | Do not |
| ncrypt | encryp |
|        | t      |
|        | the    |
|        | output |
|        | file.  |
+--------+--------+
| --no-s | Do not |
| anitiz | saniti |
| e-host | ze     |
| names  | host   |
|        | names. |
+--------+--------+
| --no-s | Do not |
| anitiz | replac |
| e-quer | e      |
| ies    | querie |
|        | s      |
|        | by     |
|        | their  |
|        | finger |
|        | prints |
|        | .      |
+--------+--------+
| --no-r | Do not |
| emove- | remove |
| temp-f | tempor |
| iles   | ary    |
|        | files. |
+--------+--------+

**Decrypt command**
^^^^^^^^^^^^^^^^^^^

| Decrypt an encrypted file. The password will be requested from the
  terminal.
| Usage:

::

    pt-secure-collect decrypt [flags] <input file>

+--------+---------+
| Flag   | Descrip |
|        | tion    |
+========+=========+
| --outf | Write   |
| ile    | the     |
|        | output  |
|        | to this |
|        | file.If |
|        | ommited |
|        | ,       |
|        | the     |
|        | output  |
|        | file    |
|        | name    |
|        | will be |
|        | the     |
|        | same as |
|        | the     |
|        | input   |
|        | file,   |
|        | adding  |
|        | the     |
|        | ``.aes` |
|        | `       |
|        | extensi |
|        | on      |
+--------+---------+

**Encrypt command**
^^^^^^^^^^^^^^^^^^^

| Encrypt a file. The password will be requested from the terminal.
| Usage:

::

    pt-secure-collect encrypt [flags] <input file>

+--------+---------+
| Flag   | Descrip |
|        | tion    |
+========+=========+
| --outf | Write   |
| ile    | the     |
|        | output  |
|        | to this |
|        | file.If |
|        | ommited |
|        | ,       |
|        | the     |
|        | output  |
|        | file    |
|        | name    |
|        | will be |
|        | the     |
|        | same as |
|        | the     |
|        | input   |
|        | file,   |
|        | without |
|        | the     |
|        | ``.aes` |
|        | `       |
|        | extensi |
|        | on      |
+--------+---------+

**Sanitize command**
^^^^^^^^^^^^^^^^^^^^

| Replace queries in a file by their fingerprints and obfuscate
  hostnames.
| Usage:

::

    pt-secure-collect sanitize [flags]

+---------------------------+------------------------------------------------------------+
| Flag                      | Description                                                |
+===========================+============================================================+
| --input-file              | Input file. If not specified, the input will be Stdin.     |
+---------------------------+------------------------------------------------------------+
| --output-file             | Output file. If not specified, the input will be Stdout.   |
+---------------------------+------------------------------------------------------------+
| --no-sanitize-hostnames   | Do not sanitize host names.                                |
+---------------------------+------------------------------------------------------------+
| --no-sanitize-queries     | Do not replace queries by their fingerprints.              |
+---------------------------+------------------------------------------------------------+
