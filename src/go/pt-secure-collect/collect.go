package main

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
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
	"github.com/percona/percona-toolkit/src/go/pt-secure-collect/sanitize"
	"github.com/percona/percona-toolkit/src/go/pt-secure-collect/sanitize/util"
	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
)

func collectData(opts *cliOptions) error {
	log.Infof("Temp directory is %q", *opts.TempDir)

	if !*opts.NoCollect {
		cmds, safeCmds, err := getCommandsToRun(defaultCmds, opts)
		// Run the commands
		if err = runCommands(cmds, safeCmds, *opts.TempDir); err != nil {
			return errors.Wrap(err, "Cannot run data collection commands")
		}
	}

	if !*opts.NoSanitize {
		log.Infof("Sanitizing output collected data")
		err := processFiles(*opts.TempDir, *opts.IncludeDirs, *opts.TempDir, !*opts.NoSanitizeHostnames, !*opts.NoSanitizeQueries)
		if err != nil {
			return errors.Wrapf(err, "Cannot sanitize files in %q", *opts.TempDir)
		}
	}

	tarFile := fmt.Sprintf(path.Join(*opts.TempDir, path.Base(*opts.TempDir)+".tar.gz"))
	log.Infof("Creating tar file %q", tarFile)
	if err := tarit(tarFile, []string{*opts.TempDir}); err != nil {
		return err
	}

	if !*opts.NoEncrypt && *opts.EncryptPassword != "" {
		password := sha256.Sum256([]byte(*opts.EncryptPassword))
		encryptedFile := tarFile + ".aes"
		log.Infof("Encrypting %q file into %q", tarFile, encryptedFile)
		encrypt(tarFile, encryptedFile, password)
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

func getCommandsToRun(defaultCmds []string, opts *cliOptions) ([]*exec.Cmd, []string, error) {
	log.Debug("Default commands to run:")
	for i, cmd := range defaultCmds {
		log.Debugf("%02d) %s", i, cmd)
	}
	cmdList := []string{}
	cmds := []*exec.Cmd{}
	safeCmds := []string{}
	notAllowedCmdsRe := regexp.MustCompile("(rm|fdisk|rmdir)")

	if !*opts.NoCollect {
		cmdList = append(cmdList, defaultCmds...)
	}

	if *opts.AdditionalCmds != nil {
		cmdList = append(cmdList, *opts.AdditionalCmds...)
	}

	for _, cmdstr := range cmdList {
		cmdstr = strings.Replace(cmdstr, "$mysql-host", *opts.MySQLHost, -1)
		cmdstr = strings.Replace(cmdstr, "$mysql-port", fmt.Sprintf("%d", *opts.MySQLPort), -1)
		cmdstr = strings.Replace(cmdstr, "$mysql-user", *opts.MySQLUser, -1)
		cmdstr = strings.Replace(cmdstr, "$temp-dir", *opts.TempDir, -1)
		safeCmd := cmdstr
		safeCmd = strings.Replace(safeCmd, "$mysql-pass", "********", -1)
		cmdstr = strings.Replace(cmdstr, "$mysql-pass", *opts.MySQLPass, -1)

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
