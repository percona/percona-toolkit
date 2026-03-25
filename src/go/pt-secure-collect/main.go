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
	"fmt"
	"io/ioutil"
	"os"
	"os/user"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/alecthomas/kong"
	"github.com/go-ini/ini"
	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
	log "github.com/sirupsen/logrus"
	"golang.org/x/crypto/ssh/terminal"
)

type cliOptions struct {
	config.ConfigFlag
	Debug bool `name:"debug" help:"Enable debug log level."`

	DecryptCommand DecryptCmd `name:"decrypt" cmd:"" help:"Decrypt an encrypted file. The password will be requested from the terminal."`

	EncryptCommand EncryptCmd `name:"encrypt" cmd:"" help:"Encrypt a file. The password will be requested from the terminal."`

	CollectCommand CollectCmd `name:"collect" cmd:"" help:"Collect, sanitize, pack and encrypt data from pt-tools."`

	SanitizeCommand SanitizeCmd `name:"sanitize" cmd:"" help:"Replace queries in a file by their fingerprints and obfuscate hostnames."`
	config.VersionFlag
	config.VersionCheckFlag
}

func (c *cliOptions) AfterApply(args ...any) error {
	if c.VersionCheck {
		advice, err := versioncheck.CheckUpdates(toolname, Version)
		if err != nil {
			log.Infof("cannot check version updates: %s", err.Error())
		} else if advice != "" {
			log.Infof("%s", advice)
		}
	}

	if c.Debug {
		log.SetLevel(log.DebugLevel)
	}

	return nil
}

type myDefaults struct {
	MySQLHost string
	MySQLPort int
	MySQLUser string
	MySQLPass string
}

const (
	toolname = "pt-secure-collect"

	decryptCmd       = "decrypt"
	encryptCmd       = "encrypt"
	collectCmd       = "collect"
	sanitizeCmd      = "sanitize"
	defaultMySQLHost = "127.0.0.1"
	defaultMySQLPort = 3306
)

var (
	CLI         = &cliOptions{}
	defaultCmds = []string{
		"pt-stalk --no-stalk --iterations=2 --sleep=30 --host=$mysql-host --dest=$temp-dir --port=$mysql-port --user=$mysql-user --password=$mysql-pass",
		"pt-summary",
		"pt-mysql-summary --host=$mysql-host --port=$mysql-port --user=$mysql-user --password=$mysql-pass",
	}

	// We do not set anything here, these variables are defined by the Makefile
	Build     string //nolint
	GoVersion string //nolint
	Version   string //nolint
	Commit    string //nolint
)

func main() {
	customFormatter := new(logrus.TextFormatter)
	customFormatter.TimestampFormat = "2006-01-02 15:04:05"
	logrus.SetFormatter(customFormatter)
	customFormatter.FullTimestamp = true

	u, err := user.Current()
	if err != nil {
		log.Fatalf("Cannot get current user: %s", err)
	}

	kCtx, _, err := config.Setup(toolname, CLI,
		kong.Description("Collect, sanitize, pack and encrypt data.\nBy default, this program will collect the output of:\n "+strings.Join(defaultCmds, "\n ")),
		kong.Vars{
			"default_temp_dir": path.Join(u.HomeDir, fmt.Sprintf("data_collection_%s", time.Now().Format("2006-01-02_15_04_05"))),
			"version": fmt.Sprintf(
				"%s\nVersion %s\nBuild: %s using %s\nCommit: %s",
				toolname, Version, Build, GoVersion, Commit,
			),
		},
	) //TODO fix help
	if err != nil {
		log.Errorf("cannot get parameters: %s", err.Error())
		os.Exit(1)
	}

	if CLI.Version {
		return
	}

	err = kCtx.Run()
	kCtx.FatalIfErrorf(err)
}

func removeTempFiles(tempDir string, removeTarFile bool) error {
	tarFile := path.Base(tempDir) + ".tar.gz"
	encryptedFile := tarFile + ".aes"
	files, err := ioutil.ReadDir(tempDir)
	if err != nil {
		return errors.Wrapf(err, "Cannot get the listing of %q", tempDir)
	}

	for _, file := range files {
		if file.Name() == encryptedFile {
			log.Infof("Skipping encrypted file %q", encryptedFile)
			continue
		}
		if file.Name() == tarFile && !removeTarFile {
			log.Infof("Skipping tar.gz file %q", tarFile)
			continue
		}

		filename := path.Join(tempDir, file.Name())
		log.Debugf("Removing file %q", filename)
		if err = os.Remove(filename); err != nil {
			log.Warnf("Cannot remove %q: %s", filename, err)
		}
	}
	return nil
}

func askMysqlPassword(user string) (string, error) {
	fmt.Printf("MySQL password for user %q:", user)
	passb, err := terminal.ReadPassword(0)
	if err != nil {
		return "", errors.Wrap(err, "Cannot read MySQL password from the terminal")
	}
	return string(passb), nil
}

func askEncryptionPassword(requireConfirmation bool) (string, error) {
	fmt.Print("Encryption password: ")
	passa, err := terminal.ReadPassword(0)
	if err != nil {
		return "", errors.Wrap(err, "Cannot read encryption password from the terminal")
	}
	fmt.Println("")
	if requireConfirmation {
		fmt.Print("Re type password: ")
		passb, err := terminal.ReadPassword(0)
		if err != nil {
			return "", errors.Wrap(err, "Cannot read encryption password confirmation from the terminal")
		}
		fmt.Println("")
		if string(passa) != string(passb) {
			return "", errors.New("Passwords don't match")
		}
	}
	return string(passa), nil
}

func getParamsFromMyCnf(configFile string) (*myDefaults, error) {
	log.Debugf("Reading default MySQL parameters from config file: %q", configFile)
	if configFile == "" {
		return nil, fmt.Errorf("Config file cannot be empty")
	}
	configFile = expandHomeDir(configFile)

	cfg, err := ini.Load(configFile)
	if err != nil {
		return nil, errors.Wrapf(err, "Cannot read config from %q", configFile)
	}

	sec, err := cfg.GetSection("client")
	if err != nil {
		return nil, errors.Wrapf(err, "Cannot read [client] section from %q", configFile)
	}

	mycnf := &myDefaults{}

	if val, err := sec.GetKey("user"); err == nil {
		mycnf.MySQLUser = val.String()
	}
	if val, err := sec.GetKey("password"); err == nil {
		mycnf.MySQLPass = val.String()
	}
	if val, err := sec.GetKey("host"); err == nil {
		mycnf.MySQLHost = val.String()
	}
	if val, err := sec.GetKey("port"); err == nil {
		if mycnf.MySQLPort, err = val.Int(); err != nil {
			return nil, errors.Wrapf(err, "Cannot parse %q as the port number", val.String())
		}
	}
	log.Debugf("mycnf: %+v\n", *mycnf)
	return mycnf, nil
}

func expandHomeDir(path string) string {
	usr, _ := user.Current()
	dir := usr.HomeDir

	if len(path) > 1 && path[:2] == "~/" {
		path = filepath.Join(dir, path[2:])
	}
	return path
}
