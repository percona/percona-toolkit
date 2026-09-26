# Percona Toolkit
[![CLA assistant](https://cla-assistant.percona.com/readme/badge/percona/percona-toolkit)](https://cla-assistant.percona.com/percona/percona-toolkit)

*Percona Toolkit* is a collection of advanced command-line tools used by
[Percona](http://www.percona.com/) support staff to perform a variety of
MySQL and system tasks that are too difficult or complex to perform manually.

These tools are ideal alternatives to private or "one-off" scripts because
they are professionally developed, formally tested, and fully documented.
They are also fully self-contained, so installation is quick and easy and
no libraries are installed.

Percona Toolkit is developed and supported by Percona Inc.  For more
information and other free, open-source software developed by Percona,
visit [http://www.percona.com/software/](http://www.percona.com/software/).

## Installation

You can install Percona Toolkit in any of the following ways:

- Install it from the Percona repository.
- Install it from a tarball.
- Build it from source.

See the [INSTALL](INSTALL) file in this directory for more information.

## Documentation

Run `man percona-toolkit` to see a list of installed tools, then run `man tool`
to read the embedded documentation for a specific tool. You can also read
the documentation online at [https://docs.percona.com/percona-toolkit/](https://docs.percona.com/percona-toolkit/).

## Submit a Bug Report or Feature Request

If you find a bug in Percona Toolkit or have a feature request, submit it to
the project's [Jira issue tracker](https://jira.percona.com/browse/PT).

Include the following information in your bug report:

- The complete command line used to run the tool
- The tool's `--version` output
- The MySQL, MongoDB, or PostgreSQL versions of all servers involved
- The tool's output, including `STDERR`
- Any input files, such as log, dump, or configuration files

If possible, also include debugging output by running the tool with `PTDEBUG=1`.

## Licensing

Percona is dedicated to keeping open source open. Whenever possible, we strive to include permissive licensing for both our software and documentation. For this project, we are using version 2 of the GNU General Public License (GPLv2).

## Contributing

We welcome contributions from anyone interested in helping improve Percona
Toolkit.

The [CONTRIBUTING.md](CONTRIBUTING.md) file contains instructions for
contributing to the project.