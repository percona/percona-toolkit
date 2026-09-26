# Contributing Guide

## How Can I Contribute?

## Reporting Bugs

Before creating a bug report, please check [this list](https://jira.percona.com/projects/PT/issues) to see whether the issue has already been reported. If you still need to file one, include as much detail as possible. You can use [this guide](https://www.percona.com/blog/2019/06/12/report-bugs-improvements-new-feature-requests-for-percona-products/) to structure the information.

### Before Submitting a Bug Report

- Read the documentation first. Percona Toolkit is a mature project with many options and behaviors, and some issues may already be explained there.
- Search [Jira](https://jira.percona.com) for an existing report before opening a new one. If the issue already exists, add a comment to the existing ticket instead of creating a duplicate.

This helps avoid duplicating work and can also reveal useful context from earlier reports or related issues.

### How Do I Submit a (Good) Bug Report?

- Explain the problem and include enough detail for others to reproduce it.
- Use a clear and descriptive title for the issue.
- Be specific about the problem: which program you are using, what the expected result is, and what result you actually saw.
- Include system details such as the language version, operating system, database version, and any relevant configuration.
- Describe the exact steps that reproduce the problem in as much detail as possible. Include the command you used and any relevant context such as OS, language, and database versions.
- Describe both the actual result and the expected result, and include examples when possible.
- Paste the error output or logs into the Jira issue, or attach them. If a file is large, you may upload it to our SFTP server. Use the Jira issue number as both the username and password for the [Percona SFTP server](sftp.percona.com). Include the Jira issue number in the file name and add a comment so we can access it.

## Reporting Documentation Issues

Documentation bugs for Percona Toolkit should be reported in [Percona Jira](https://jira.percona.com/) under the **PT** project with the **Documentation** component.

### Good Documentation Bug Report

- Includes a link to the user manual page where the documentation is wrong.
- Clearly explains the problem.
- Optionally explains how the documentation should be fixed.

## Introducing Changes to the Toolkit

### Set Up the Source Code

To start, fork the Percona Toolkit repository so you can submit pull requests and clone it locally:

```bash
mkdir ${HOME}/perldev
git clone https://github.com/percona/percona-toolkit.git ${HOME}/perldev/percona-toolkit
```

### Create a New Branch

Create your own development branch. If you have a Jira ticket assigned, use its number as a reference and add a short description of the work this branch will do:

```bash
git checkout -b PT-9999_functionality_name
```

Use the Jira reference number at the beginning of the first commit message so Jira can use the smart tags.

### Example Commit Message

```
PT-12345 - fixed data corruption issue for pt-foo

New check pt-foo-test-env added when pt-foo is going to perform destructive operation.
If check fails, now pt-foo will stop executing and return an error.
```

### Changing Shared Code

Percona Toolkit uses the `lib` directory for shared library code. After changing a library, run the `update-modules` tool so the generated code in each tool is updated as well. Be careful not to modify anything between the `This package is a copy without comments from the original` and `End ... package` comments.

### Running the update-modules Tool

Whenever you change code under `lib/`, run `util/update-modules` so every tool that uses those packages picks up the new changes. For example, if you changed `lib/bash/collect.sh`, run:

```bash
cd ${HOME}/perldev/percona-toolkit
for t in bin/*; do util/update-modules ${t} collect; done
```

If you changed `lib/NibbleIterator.pm`, run:

```bash
cd ${HOME}/perldev/percona-toolkit
for t in bin/*; do util/update-modules ${t} NibbleIterator; done
```

If no module is specified, all modules will be updated.

## Uploading Your Branch

After you run another round of tests and everything passes, upload your branch to your GitHub fork:

```bash
git push origin PT-9999_functionality_name
```

Then open the web UI and create a pull request (PR) from this branch.

## Submitting Fixes
### Pull Requests
Once your fix is ready and you pushed it into the feature branch, open a pull request with the code. Be sure you’ve read any documents on contributing, understand the license and have signed <a href="https://goo.gl/forms/pfjaTq2akPDLqtaJ2">the Individual Contributor License Agreement</a> or <a href="https://goo.gl/forms/ZuXlckMyblaLwQr52">the Corporate Contributor License Agreement</a> [Contributor Licence Agreement (CLA)](https://github.com/percona/percona-toolkit/blob/3.x/CONTRIBUTING.md). Once you’ve submitted a pull request, the maintainers can compare your branch to the existing one and decide whether or not to incorporate (merge) your changes.

### Tips for Creating a Pull Request
- Be clear about the problem you fixed or the feature you added. Include explanations and code references to help the maintainers understand what you did.
- Add useful comments to the code to help others understand it.
- Write tests. This is an important step. Run your changes against existing tests and create new ones when needed. Whether tests exist or not, make sure your changes don’t break the existing project.
- Contribute in the style of the project to the best of your abilities. This may mean using indents, semicolons, or comments differently than you would in your own repository, but makes it easier for the maintainer to merge, others to understand and maintain in the future.
- Keep your changes as small as possible and solve only what's reported in the issue. Mixing fixes might be confusing to others and makes testing harder.
- Be as explicit as possible. Avoid using special/internal language variables like `$_`. Use a variable name that clearly represents the value it holds.
- Write good commit messages. A comment like *'Misc bugfixes'* or *'More code added'* does not help to understand what's the change about.
- Put Jira issue number into the commit message to automatically link it with the Jira issue.

### Open a Pull Request
Once you’ve opened a pull request, a discussion will start around your proposed changes. Other contributors and users may chime in, but ultimately the decision is made by the maintainers. You may be asked to make some changes to your pull request, if so, add more commits to your branch and push them – they’ll automatically go into the existing pull request.

## Licensing
Along with the pull request, include a message indicating that the submitted code is your own creation and it can be distributed under the GPL2 licence.


## Setting up the Development Environment and Testing
### Perl and Shell Tools
For testing, we are going to need to have MySQL with replicas. For that, we already have scripts in the sandbox directory but first we need to download MySQL binaries. Please download the Linux Generic tar file for your distribution from [https://www.percona.com/downloads/](https://www.percona.com/downloads/).

#### Set up MySQL Sandbox
In this example, we are going to download Percona Server 9.7.1-1

```
mkdir -p ${HOME}/mysql/percona-server-9.7.1-1
```
```
wget https://downloads.percona.com/downloads/Percona-Server-9.7/Percona-Server-9.7.1-1/binary/tarball/Percona-Server-9.7.1-1-Linux.x86_64.glibc2.28.tar.gz
```
```
tar xvzf Percona-Server-9.7.1-1-Linux.x86_64.glibc2.28.tar.gz --strip 1 -C ${HOME}/mysql/percona-server-8.0.26-17
```
#### Set Up Environment Variables
We need these environment variables to start the MySQL sandbox and to run the tests. Probably it is a good idea to add them to your `.bashrc` file.
```
export PERCONA_TOOLKIT_SANDBOX=$HOME/mysql/percona-server-9.7.1-1
export PERCONA_TOOLKIT_BRANCH=`pwd`
export BRANCH=$(git rev-parse --abbrev-ref HEAD)
export MYSQL_VERSION=9.7
export LOG_FILE=~/${BRANCH}-${MYSQL_VERSION}.log
```

#### Check That All Needed Tools Are Correctly Installed:
```
util/check-dev-env
```
If not, you will have to either install them via your package manager of preference, or using Perl directly. For example, let's assume that you are missing the `File::Slurp` package (as flagged by a `NA` output from the previous command), you can use:
```
sudo perl -MCPAN -e "shell"
cpan[1]> install File::Slurp
...
```

#### Starting the Sandbox
```
cd ${HOME}/perldev/percona-toolkit
```
```
sandbox/test-env start
```
To stop the MySQL sandbox: `sandbox/test-env stop`
To enable TokuDB (only available in Percona Server 5.7 and Percona Server 8.0), run:

```
ENABLE_TOKUDB=1 sandbox/test-env start
```

To enable MyRocks (only available in Percona Server 5.7+), run:

```
ENABLE_ROCKSDB=1 sandbox/test-env start
```

#### Running Tests
```
cd ${HOME}/perldev/percona-toolkit
```
Run all tests for a particular program (pt-stalk in this example):
```
prove -v t/pt-stalk/
```
You can also add warnings with:
```
prove -vw t/pt-stalk/
```
or run a specific test:
```
prove -v t/pt-stalk/option_sanity.t
```

### Go Tools

Starting from version 3, there are new tools for MongoDB, PostgreSQL, Kubernetes, written in Go language.

To test these tools, first switch to the `src/go` directory, then use command `make`.

#### Starting the Sandbox

For some of MongoDB and PostgreSQL tools, you need to start the sandbox. Run command `make env-up`. This will start MongoDB and PostgreSQL container clusters. For other tools, sandbox is created by the test files themselves. This inconsistency will change in the future, but at this moment, you need to test each tool individually.

#### Testing

cd into the individual tool directory, and run `go test`.

#### Stopping the Sandbox

Run `make env-down`.