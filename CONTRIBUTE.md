#Contributing guide
##How Can I Contribute?
##Reporting Bugs
Before creating bug reports, please check this list as you might find out that you don't need to create one. When you create a bug report, please include as many details as possible. You can use this template to structure the information.  

###Before Submitting A Bug Report
- Ensure you have carefully read the documentation. Percona Toolkit is a mature project with many settings that covers a wide range options.
- Search for existing bugs in Launchpad to see if the problem has already been reported. If it has, add a comment to the existing issue instead of opening a new one.

###How Do I Submit A (Good) Bug Report?
- Explain the problem and include additional details to help others reproduce the problem:
- Use a clear and descriptive title for the issue to identify the problem.
- Describe the exact steps which reproduce the problem, including as many details as possible. Provide examples of the command you used and include context information like language, OS and database versions.
Describe the obtained results and the expected results and, if it is possible, provide examples.

##Submiting fixes
###Create an Issue
If you find a bug, the first step is to create an issue. Whatever the problem is, you’re likely not the only one experiencing it. Others will find your issue helpful, and other developers might help you find the cause and discuss the best solution for it.

####Tips for creating an issue
- Check if there are any existing issues for your problem. By doing this, we can avoid duplicating efforts, since the issue might have been already reported and if not, you might find useful information on older issues related to the same problem.
- Be clear about what your problem is: which program were you using, what was the expected result and what is the result you are getting. Detail how someone else can reproduce the problem, including examples.
- Include system details like language version, OS, database details or special configurations, etc.
- Paste the error output or logs in your issue or in a Gist.

###Pull Requests
If you fixed a bug or added a new feature – awesome! Open a pull request with the code! Be sure you’ve read any documents on contributing, understand the license and have signed a Contributor Licence Agreement (CLA) if required. Once you’ve submitted a pull request, the maintainers can compare your branch to the existing one and decide whether or not to incorporate (merge) your changes.

###Tips for creating a pull request
- Fork the repository and clone it locally. Connect your local to the original ‘upstream’ repository by adding it as a remote. Pull in changes from ‘upstream’ often so that you stay up to date so that when you submit your pull request, merge conflicts will be less likely.
- Create a branch for your code. Usually it is a good practice to name the branch after the issue ID, like issue-12345.
- Be clear about the problem you fixed or the feature you added. Include explanations and code references to help the maintainers understand what you did.
- Add useful comments to the code to help others understand it.
- Write tests. This is an important step. Run your changes against existing tests and create new ones when needed. Whether tests exist or not, make sure your changes don’t break the existing project.
- Contribute in the style of the project to the best of your abilities. This may mean using indents, semicolons, or comments differently than you would in your own repository, but makes it easier for the maintainer to merge, others to understand and maintain in the future.
- Keep your changes as small as possible and solve only what's reported in the issue. Mixing fixes might be confusing to others and makes testing harder.
- Be as explicit as possible. Avoid using special/internal language variables like $_. Use a variable name that clearly represents the value it holds.
- Write good commit messages. A comment like 'Misc bugfixes' or 'More code added' does not help to understand what's the change about.

###Open Pull Requests
Once you’ve opened a pull request, a discussion will start around your proposed changes. Other contributors and users may chime in, but ultimately the decision is made by the maintainers. You may be asked to make some changes to your pull request, if so, add more commits to your branch and push them – they’ll automatically go into the existing pull request.

#Licensing
Along with the pull request, include a message indicating that the submited code is your own creation and it can be distributed under the BSD licence. 
  
  
#Setting up the development environment

####Setting up the source code
To start, fork the Percona Toolkit repo to be able to submit pull requests and clone it locally:
```
mkdir ${HOME}/perldev
git clone https://github.com/<your-username>/percona-toolkit.git ${HOME}/perldev/percona-toolkit
```

For testing, we are going to need to have MySQL with slaves. For that, we already have scripts in the sandbox directory but first we need to download MySQL binaries. Please download the Linux Generic tar file for your distrubution from [https://www.percona.com/downloads/Percona-Server-5.6/](https://www.percona.com/downloads/Percona-Server-5.6/).    

###Set up MySQL sandbox
In this example, we are going to download Percona Server 5.6.32. Since I am using Ubuntu, according to the documentation [here](https://www.percona.com/doc/percona-server/5.6/installation.html#installing-percona-server-from-a-binary-tarball), I am going to need this tar file: [Percona-Server-5.6.32-rel78.1-Linux.x86_64.ssl100.tar.gz](https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.32-78.1/binary/tarball/Percona-Server-5.6.32-rel78.1-Linux.x86_64.ssl100.tar.gz).  

```
mkdir -p ${HOME}/mysql/percona-server-5.6.32
```
```
wget https://www.percona.com/downloads/Percona-Server-5.6/Percona-Server-5.6.32-78.1/binary/tarball/Percona-Server-5.6.32-rel78.1-Linux.x86_64.ssl100.tar.gz 
```
```
tar xvzf Percona-Server-5.6.32-rel78.1-Linux.x86_64.ssl100.tar.gz --strip 1 -C ${HOME}/mysql/percona-server-5.6.32
```
###Set up environment variables:
We need these environment variables to start the MySQL sandbox and to run the tests. Probably it is a good idea to add them to your `.bashrc` file.
```
export PERCONA_TOOLKIT_BRANCH=${HOME}/perldev/percona-toolkit
export PERL5LIB=${HOME}/perldev/percona-toolkit/lib
export PERCONA_TOOLKIT_SANDBOX=${HOME}/mysql/percona-server-5.6.32
```

###Starting the sandbox
```
cd ${HOME}/perldev/percona-toolkit
```
```
sandbox/test-env start
```
To stop the MySQL sandbox: `sandbox/test-env stop`  

###Running tests
```
cd ${HOME}/perldev/percona-toolkit
```
Run all tests for a particular program (pt-stalk in this example):
```
prove -v t/pt-stalk/
```
or run a specific test:
```
prove -v t/pt-stalk/option_sanity.t
```

