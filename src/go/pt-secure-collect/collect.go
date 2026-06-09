// This program is copyright 2018-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"os/exec"
	"os/user"
	"path"
	"regexp"
	"strings"
	"time"

	shellwords "github.com/mattn/go-shellwords"
	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"

	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/pt-secure-collect/sanitize"
	"github.com/percona/percona-toolkit/src/go/pt-secure-collect/sanitize/util"
)

type CollectCmd struct {
	BinDir      string                    `name:"bin-dir" help:"Directory having the Percona Toolkit binaries (if they are not in PATH)."`
	TempDir     string                    `name:"temp-dir" help:"Temporary directory used for the data collection." default:"${default_temp_dir}"` // in case Percona Toolkit is not in the PATH
	IncludeDirs []string                  `name:"include-dir" help:"Include this dir into the sanitized tar file"`
	ConfigFile  string                    `name:"config-file" help:"Path to the config file." default:"~/.my.cnf"` // .my.cnf file
	MySQLHost   string                    `name:"mysql-host" help:"MySQL host."`
	MySQLPort   int                       `name:"mysql-port" help:"MySQL port."`
	MySQLUser   string                    `name:"mysql-user" help:"MySQL user name."`
	MySQLPass   config.StdinRequestString `name:"mysql-password" help:"MySQL password."` //TODO: list in changed

	AdditionalCmds  []string                  `name:"extra-cmd" help:"Also run this command as part of the data collection. This parameter can be used more than once."`
	EncryptPassword config.StdinRequestString `name:"encrypt-password" help:"Encrypt the output file using this password. If omitted, the file won't be encrypted."` // if set, it will produce an encrypted .aes file

	Encrypt           bool `name:"collect" negatable:"" default:"true"`
	Sanitize          bool `name:"sanitize" negatable:"" default:"true"`
	SanitizeHostnames bool `name:"encrypt" negatable:"" default:"true"`
	SanitizeQueries   bool `name:"sanitize-hostnames" negatable:"" default:"true"`
	Collect           bool `name:"sanitize-queries" negatable:"" default:"true"`
	RemoveTempFiles   bool `name:"remove-temp-files" negatable:"" default:"true"`
}

func (c *CollectCmd) AfterApply(args ...any) error {
	err := c.ParseMySQLConfig()
	if err != nil {
		return err
	}

	err = c.MySQLPass.Request(func() (string, error) {
		return askMysqlPassword(c.MySQLUser)
	})
	if err != nil {
		return err
	}

	err = c.EncryptPassword.Request(func() (string, error) {
		if !c.Encrypt {
			return "", nil
		}
		return askEncryptionPassword(true)
	})
	if err != nil {
		return err
	}

	c.BinDir = expandHomeDir(c.BinDir)
	c.ConfigFile = expandHomeDir(c.ConfigFile)
	c.TempDir = expandHomeDir(c.TempDir)
	for _, incDir := range c.IncludeDirs {
		incDir = expandHomeDir(incDir)
	}

	if c.BinDir != "" {
		os.Setenv("PATH", fmt.Sprintf("%s%s%s", c.BinDir, string(os.PathListSeparator), os.Getenv("PATH")))
	}

	lp, err := exec.LookPath("pt-summary")
	if (err != nil || lp == "") && c.BinDir == "" && c.Collect {
		return errors.New("Cannot find Percona Toolkit binaries. Please run this tool again using --bin-dir parameter")
	}

	return nil
}

func (c *CollectCmd) ParseMySQLConfig() error {
	mycnf, err := getParamsFromMyCnf(c.ConfigFile)
	if err != nil {
		return err
	}

	if c.MySQLPort == 0 && mycnf.MySQLPort > 0 {
		log.Debugf("Setting default port from config file")
		c.MySQLPort = mycnf.MySQLPort
	}
	if c.MySQLHost == "" && mycnf.MySQLHost != "" {
		c.MySQLHost = mycnf.MySQLHost
		log.Debugf("Setting default host from config file")
	}
	if c.MySQLUser == "" && mycnf.MySQLUser != "" {
		log.Debugf("Setting default user from config file")
		c.MySQLUser = mycnf.MySQLUser
	}
	if c.MySQLPass == "" && mycnf.MySQLPass != "" {
		log.Debugf("Setting default password from config file")
		c.MySQLPass = config.StdinRequestString(mycnf.MySQLPass)
	}

	if c.MySQLHost == "" {
		log.Debugf("MySQL host is empty. Setting it to %s", defaultMySQLHost)
		c.MySQLHost = defaultMySQLHost
	}
	if c.MySQLPort == 0 {
		log.Debugf("MySQL port is empty. Setting it to %d", defaultMySQLPort)
		c.MySQLPort = defaultMySQLPort
	}
	if c.MySQLUser == "" {
		return fmt.Errorf("MySQL user cannot be empty")
	}

	return nil
}

func (c *CollectCmd) Run() error {
	log.Infof("Temp directory is %q", c.TempDir)

	if c.Collect {
		cmds, safeCmds, err := c.getCommandsToRun(defaultCmds)
		// Run the commands
		if err = runCommands(cmds, safeCmds, c.TempDir); err != nil {
			return errors.Wrap(err, "Cannot run data collection commands")
		}
	}

	if c.Sanitize {
		log.Infof("Sanitizing output collected data")
		err := processFiles(c.TempDir, c.IncludeDirs, c.TempDir, c.SanitizeHostnames, c.SanitizeQueries)
		if err != nil {
			return errors.Wrapf(err, "Cannot sanitize files in %q", c.TempDir)
		}
	}

	tarFile := path.Join(c.TempDir, path.Base(c.TempDir)+".tar.gz")
	log.Infof("Creating tar file %q", tarFile)
	if err := tarit(tarFile, []string{c.TempDir}); err != nil {
		return err
	}

	if c.Encrypt {
		key, err := deriveKey(string(c.EncryptPassword))
		if err != nil {
			return errors.WithStack(err)
		}

		encryptedFile := tarFile + ".aes"
		log.Infof("Encrypting %q file into %q", tarFile, encryptedFile)
		encrypt(tarFile, encryptedFile, key)
	}

	return nil
}

func processFiles(dataDir string, includeDirs []string, outputDir string, sanitizeHostnames, sanitizeQueries bool) error {
	dirs := []string{dataDir}
	dirs = append(dirs, includeDirs...)

	for _, dir := range dirs {
		files, err := ioutil.ReadDir(dir)
		if err != nil {
			return errors.Wrapf(err, "Cannot get the listing of %q", dir)
		}
		if len(files) == 0 {
			return errors.Errorf("There are no files to sanitize in %q", dir)
		}
		log.Debug("Sanitization process start")

		for _, file := range files {
			if file.IsDir() {
				continue
			}
			inputFile := path.Join(dir, file.Name())
			log.Debugf("Reading %q", inputFile)
			fh, err := os.Open(inputFile)
			if err != nil {
				return errors.Wrapf(err, "Cannot open %q for reading", inputFile)
			}

			lines, err := util.ReadLinesFromFile(fh)
			if err != nil {
				return errors.Wrapf(err, "Cannot sanitize %q", inputFile)
			}

			log.Debugf("Sanitizing %q", inputFile)
			sanitized := sanitize.Sanitize(lines, sanitizeHostnames, sanitizeQueries)

			outfile := path.Join(outputDir, file.Name())
			log.Debugf("Writing sanitized file to %q", outfile)
			ofh, err := os.Create(outfile)
			if err != nil {
				return errors.Wrapf(err, "Cannot open %q for writing", outfile)
			}

			if err = util.WriteLinesToFile(ofh, sanitized); err != nil {
				return errors.Wrapf(err, "Cannot write sanitized file %q", outfile)
			}
		}
	}
	return nil
}

func tarit(outfile string, srcPaths []string) error {
	file, err := os.Create(outfile)
	if err != nil {
		return errors.Wrapf(err, "Cannot create tar file %q", outfile)
	}
	defer file.Close()

	gw := gzip.NewWriter(file)
	defer gw.Close()

	tw := tar.NewWriter(gw)
	defer tw.Close()

	for _, srcPath := range srcPaths {
		files, err := ioutil.ReadDir(srcPath)
		if err != nil {
			return errors.Wrapf(err, "Cannot get the listing of %q", srcPath)
		}
		for _, file := range files {
			// Ignore tar.gz files from previous runs
			if strings.HasSuffix(file.Name(), ".tar.gz") {
				log.Debugf("Skipping file %q", file.Name())
				continue
			}
			log.Debugf("Adding %q to the tar file", file.Name())
			if err := addFile(tw, srcPath, file); err != nil {
				return errors.Wrapf(err, "Cannot add %q to the tar file %q", file.Name(), outfile)
			}
		}
	}

	return nil
}

func (c *CollectCmd) getCommandsToRun(defaultCmds []string) ([]*exec.Cmd, []string, error) {
	log.Debug("Default commands to run:")
	for i, cmd := range defaultCmds {
		log.Debugf("%02d) %s", i, cmd)
	}
	cmdList := []string{}
	cmds := []*exec.Cmd{}
	safeCmds := []string{}
	notAllowedCmdsRe := regexp.MustCompile("(rm|fdisk|rmdir)")

	if c.Collect {
		cmdList = append(cmdList, defaultCmds...)
	}

	if c.AdditionalCmds != nil {
		cmdList = append(cmdList, c.AdditionalCmds...)
	}

	for _, cmdstr := range cmdList {
		cmdstr = strings.Replace(cmdstr, "$mysql-host", c.MySQLHost, -1)
		cmdstr = strings.Replace(cmdstr, "$mysql-port", fmt.Sprintf("%d", c.MySQLPort), -1)
		cmdstr = strings.Replace(cmdstr, "$mysql-user", c.MySQLUser, -1)
		cmdstr = strings.Replace(cmdstr, "$temp-dir", c.TempDir, -1)
		safeCmd := cmdstr
		safeCmd = strings.Replace(safeCmd, "$mysql-pass", "********", -1)
		cmdstr = strings.Replace(cmdstr, "$mysql-pass", string(c.MySQLPass), -1)

		args, err := shellwords.Parse(cmdstr)
		if err != nil {
			return nil, nil, errors.Wrapf(err, "Cannot parse %q", cmdstr)
		}
		if found := notAllowedCmdsRe.FindAllString(args[0], -1); len(found) > 0 {
			continue
		}

		cmd := exec.Command(args[0], args[1:]...)
		cmds = append(cmds, cmd)
		safeCmds = append(safeCmds, safeCmd)
	}
	return cmds, safeCmds, nil
}

func runCommands(cmds []*exec.Cmd, safeCmds []string, dataDir string) error {
	for i := range cmds {
		cmd := cmds[i]
		safeCmd := safeCmds[i]

		logFile := path.Join(dataDir, fmt.Sprintf("%s_%s.out", path.Base(cmd.Args[0]), time.Now().Format("2006-01-02_15_04_05")))
		log.Infof("Creating output file %q", logFile)
		fh, err := os.Create(logFile)
		if err != nil {
			return errors.Wrapf(err, "Cannot create output file %s", logFile)
		}

		log.Infof("Running %s", safeCmd)
		stdoutStderr, err := cmd.CombinedOutput()
		if err != nil {
			fh.WriteString(fmt.Sprintf("There was a problem running %s\n%s", safeCmd, err))
			fh.Write(stdoutStderr)
			fh.Close()
			return errors.Wrapf(err, "\nThere was a problem running %s\n%s",
				safeCmd, fmt.Sprintf("See %s for more details.", logFile))
		}
		fh.Write(stdoutStderr)
		fh.Close()
	}

	return nil
}

func addFile(tw *tar.Writer, srcPath string, fileInfo os.FileInfo) error {
	file, err := os.Open(path.Join(srcPath, fileInfo.Name()))
	if err != nil {
		return err
	}
	defer file.Close()

	if _, err := file.Stat(); err == nil {
		header, err := tar.FileInfoHeader(fileInfo, "")
		if err != nil {
			return errors.Wrapf(err, "Cannot create tar file header for %q", fileInfo.Name())
		}

		// Add the path since fileInfo.Name() only has the file name without the path
		header.Name = path.Join(path.Base(srcPath), fileInfo.Name())

		if err := tw.WriteHeader(header); err != nil {
			return errors.Wrapf(err, "Cannot write file header for %q into the tar file", fileInfo.Name())
		}

		if _, err := io.Copy(tw, file); err != nil {
			return errors.Wrapf(err, "Cannot write file %q to the tar file", fileInfo.Name())
		}
	}
	return nil
}

func getTempDir() (string, error) {
	user, err := user.Current()
	if err != nil {
		return "", errors.Wrap(err, "Cannot get current user information")
	}

	dir, err := ioutil.TempDir(user.HomeDir, "sanitize_")
	if err != nil {
		return "", errors.Wrap(err, "Cannot create temporary directory")
	}

	return dir, nil
}
