# Contributing Guide
## How Can I Contribute?
## Reporting Bugs
Before creating bug reports, please check [this list](https://jira.percona.com/projects/PT/issues) as you might find out that you don't need to create one. When you create a bug report, please include as many details as possible. You can use [this guide](https://www.percona.com/blog/2019/06/12/report-bugs-improvements-new-feature-requests-for-percona-products/) to structure the information.

### Before Submitting a Bug Report
- Ensure you have carefully read the documentation. Percona Toolkit is a mature project with many settings that cover a wide range of options.
- Search for existing bugs in [Jira](https://jira.percona.com) to see if the problem has already been reported. If it has, add a comment to the existing issue instead of opening a new one.
By doing this, we can avoid duplicating efforts, since the issue might have been already reported and if not, you might find useful information on older issues related to the same problem.

### How Do I Submit a (Good) Bug Report?
- Explain the problem and include additional details to help others to reproduce the problem.
- Use a clear and descriptive title for the issue.
- Be clear about what your problem is: which program you are using, what is the expected result and what is the result you are getting.
- Include system details, such as language version, OS, database details or special configurations, etc.
- Describe the exact steps which reproduce the problem, including as many details as possible. Provide examples of the command you used and include context information like language, OS and database versions.
- Describe the obtained and the expected results and, if possible, provide examples.
- Paste the error output or logs into Jira issue or attach them. You may put large files on our SFTP server if needed. Use Jira issue number as a login and password for the [Percona SFTP server](sftp.percona.com). Have Jira issue number in the file name and add a comment, so we can access it.

## Reporting Documentation Issues
Documentation bugs for Percona Toolkit should be reported at [Percona Jira](https://jira.percona.com/) in the project **PT** and have component **Documentation**.

### Good Documentation Bug Report
- Contains link to the user manual page where the documentation is wrong
- Fully explains the problem
- Optionally explains how documentation should be fixed

## Introducing Changes to the Toolkit
### Set Up the Source Code
To start, fork the Percona Toolkit repo to be able to submit pull requests and clone it locally:
```
mkdir ${HOME}/perldev
git clone https://github.com/percona/percona-toolkit.git ${HOME}/perldev/percona-toolkit
```
### Create a New Branch

You should start your own development branch. If you have a Jira ticket assigned, use its number as a reference, and add a short description of what work on this branch will do:
```
git checkout -b PT-9999_functionality_name
```
The first commit should also have the Jira reference number as first characters in the commit message (so that Jiraf can use the smart tags).

### Example Commit Message

```
PT-12345 - fixed data corruption issue for pt-foo

New check pt-foo-test-env added when pt-foo is going to perform destructive operation.
If check fails, now pt-foo will stop executing and return an error.
```

### Changing Shared Code

Percona Toolkit uses `lib` directory for library code. Once you change it you need to run the `update-modules` tool that will merge module code with the tools. Be careful and **do not modify** anything between the `This package is a copy without comments from the original`  and `End ... package` comments.

### Running the update-modules Tool

Whenever you make changes to libraries under `lib/`, you should make sure that you run the `util/update-modules` functionality, to make sure that all tools that use these packages will benefit from the new changes. For example, let's say you changed the `lib/bash/collect.sh` package, you will need to run:
```
cd ${HOME}/perldev/percona-toolkit
for t in bin/*; do util/update-modules ${t} collect; done
```
Or if you changed the `lib/NibbleIterator.pm` package:
```
cd ${HOME}/perldev/percona-toolkit
for t in bin/*; do util/update-modules ${t} NibbleIterator; done
```

## Uploading Your Branch

Finally, after you run another round of tests and everything is OK, you should upload your branch to your GitHub fork:
```
git push origin PT-9999_functionality_name
```
And then go to the web UI to create the new pull request (PR) based off of this new branch.

## Submitting Fixes
### Pull Requests
Once your fix is ready and you pushed it into the feature branch, open a pull request with the code. Be sure you’ve read any documents on contributing, understand the license and have signed a [Contributor Licence Agreement (CLA)](https://github.com/percona/percona-toolkit/blob/3.x/CONTRIBUTING.md). Once you’ve submitted a pull request, the maintainers can compare your branch to the existing one and decide whether or not to incorporate (merge) your changes.

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
For testing, we are going to need to have MySQL with replicas. For that, we already have scripts in the sandbox directory but first we need to download MySQL binaries. Please download the Linux Generic tar file for your distribution from [https://www.percona.com/downloads/Percona-Server-LATEST/](https://www.percona.com/downloads/Percona-Server-LATEST/).

#### Set up MySQL Sandbox
In this example, we are going to download Percona Server 8.0.26-17.

```
mkdir -p ${HOME}/mysql/percona-server-8.0.26-17
```
```
wget https://downloads.percona.com/downloads/Percona-Server-LATEST/Percona-Server-8.0.26-17/binary/tarball/Percona-Server-8.0.26-17-Linux.x86_64.glibc2.17.tar.gz
```
```
tar xvzf Percona-Server-8.0.26-17-Linux.x86_64.glibc2.17.tar.gz --strip 1 -C ${HOME}/mysql/percona-server-8.0.26-17
```
#### Set Up Environment Variables
We need these environment variables to start the MySQL sandbox and to run the tests. Probably it is a good idea to add them to your `.bashrc` file.
```
export PERCONA_TOOLKIT_BRANCH=${HOME}/perldev/percona-toolkit
export PERL5LIB=${HOME}/perldev/percona-toolkit/lib
export PERCONA_TOOLKIT_SANDBOX=${HOME}/mysql/percona-server-8.0.26-17
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
To enable TokuDB (only available in Percona Server 5.7+), run:

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

Starting from version 3, there are new tools for MongoDB, written in Go language.

To test these tools, first switch to the `src/go` directory, then use command `make`.

#### Starting the Sandbox

Run command `make env-up`. This will start MongoDB container cluster

#### Build Mongo Tools

Run command `make` with your environment as a parameter. For example, `make linux-amd64` will build Mongo tools for Linux AMD64 platform.

#### Running Tests

Run `make test`

#### Stopping the Sandbox

Run `make env-down`
