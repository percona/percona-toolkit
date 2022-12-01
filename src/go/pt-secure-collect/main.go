package main

import (
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"os/exec"
	"os/user"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/alecthomas/kingpin"
	"github.com/go-ini/ini"
	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
	log "github.com/sirupsen/logrus"
	"golang.org/x/crypto/ssh/terminal"
)

type cliOptions struct {
	Command string
	Debug   *bool

	DecryptCommand *kingpin.CmdClause
	DecryptInFile  *string
	DecryptOutFile *string

	EncryptCommand *kingpin.CmdClause
	EncryptInFile  *string
	EncryptOutFile *string

	CollectCommand  *kingpin.CmdClause
	BinDir          *string
	TempDir         *string // in case Percona Toolkit is not in the PATH
	IncludeDirs     *[]string
	ConfigFile      *string // .my.cnf file
	EncryptPassword *string // if set, it will produce an encrypted .aes file
	AdditionalCmds  *[]string
	AskMySQLPass    *bool
	MySQLHost       *string
	MySQLPort       *int
	MySQLUser       *string
	MySQLPass       *string

	NoEncrypt           *bool
	NoSanitize          *bool
	NoSanitizeHostnames *bool
	NoSanitizeQueries   *bool
	NoCollect           *bool
	NoRemoveTempFiles   *bool

	SanitizeCommand       *kingpin.CmdClause
	SanitizeInputFile     *string
	SanitizeOutputFile    *string
	DontSanitizeHostnames *bool
	DontSanitizeQueries   *bool
}

type myDefaults struct {
	MySQLHost string
	MySQLPort int
	MySQLUser string
	MySQLPass string
}

const (
	TOOLNAME = "pt-secure-collect"

	decryptCmd       = "decrypt"
	encryptCmd       = "encrypt"
	collectCmd       = "collect"
	sanitizeCmd      = "sanitize"
	defaultMySQLHost = "127.0.0.1"
	defaultMySQLPort = 3306
)

var (
	defaultCmds = []string{
		"pt-stalk --no-stalk --iterations=2 --sleep=30 --host=$mysql-host --dest=$temp-dir --port=$mysql-port --user=$mysql-user --password=$mysql-pass",
		"pt-summary",
		"pt-mysql-summary --host=$mysql-host --port=$mysql-port --user=$mysql-user --password=$mysql-pass",
	}

	Build     string = "2020-04-23" //nolint
	GoVersion string = "1.14.1"     //nolint
	Version   string = "3.5.0"      //nolint
	Commit    string                //nolint
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

	opts, err := processCliParams(u.HomeDir, nil)
	if err != nil {
		log.Fatal(err)
	}

	switch opts.Command {
	case collectCmd:
		if _, err = os.Stat(*opts.TempDir); os.IsNotExist(err) {
			log.Infof("Creating temporary directory: %s", *opts.TempDir)
			if err = os.Mkdir(*opts.TempDir, os.ModePerm); err != nil {
				log.Fatalf("Cannot create temporary dirextory %q: %s", *opts.TempDir, err)
			}
		}
		err = collectData(opts)
		if err != nil && !*opts.NoRemoveTempFiles {
			log.Fatal(err)
		}
		if !*opts.NoRemoveTempFiles {
			if err = removeTempFiles(*opts.TempDir, !*opts.NoEncrypt); err != nil {
				log.Fatal(err)
			}
		}
	case encryptCmd, decryptCmd:
		err = encryptorCmd(opts)
	case sanitizeCmd:
		err = sanitizeFile(opts)
	}
	if err != nil {
		log.Fatal(err)
	}
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

func processCliParams(baseTempPath string, usageWriter io.Writer) (*cliOptions, error) {
	var err error
	tmpdir := path.Join(baseTempPath, fmt.Sprintf("data_collection_%s", time.Now().Format("2006-01-02_15_04_05")))

	// Do not remove the extra space after \n. That's to trick the help template to not to remove the new line
	msg := "Collect, sanitize, pack and encrypt data.\nBy default, this program will collect the output of:"
	for _, cmd := range defaultCmds {
		msg += "\n " + cmd
	}
	msg += "\n "

	app := kingpin.New(TOOLNAME, msg)
	if usageWriter != nil {
		app.UsageWriter(usageWriter)
		app.Terminate(nil)
	}

	// Add support for --version flag
	app.Version(TOOLNAME + "\nVersion " + Version + "\nBuild: " + Build + " using " + GoVersion +
		" Go version: " + GoVersion)

	opts := &cliOptions{
		CollectCommand:  app.Command(collectCmd, "Collect, sanitize, pack and encrypt data from pt-tools."),
		DecryptCommand:  app.Command(decryptCmd, "Decrypt an encrypted file. The password will be requested from the terminal."),
		EncryptCommand:  app.Command(encryptCmd, "Encrypt a file. The password will be requested from the terminal."),
		SanitizeCommand: app.Command(sanitizeCmd, "Replace queries in a file by their fingerprints and obfuscate hostnames."),
		Debug:           app.Flag("debug", "Enable debug log level.").Bool(),
	}
	// Decrypt command flags
	opts.DecryptInFile = opts.DecryptCommand.Arg("infile", "Encrypted file.").Required().String()
	opts.DecryptOutFile = opts.DecryptCommand.Flag("outfile", "Unencrypted file. Default: same name without .aes extension").String()

	// Encrypt command flags
	opts.EncryptInFile = opts.EncryptCommand.Arg("infile", "Unencrypted file.").Required().String()
	opts.EncryptOutFile = opts.EncryptCommand.Flag("outfile", "Encrypted file. Default: <input file>.aes").String()

	// Collect command flags
	opts.BinDir = opts.CollectCommand.Flag("bin-dir", "Directory having the Percona Toolkit binaries (if they are not in PATH).").String()
	opts.TempDir = opts.CollectCommand.Flag("temp-dir", "Temporary directory used for the data collection.").Default(tmpdir).String()
	opts.IncludeDirs = opts.CollectCommand.Flag("include-dir", "Include this dir into the sanitized tar file").Strings()
	// MySQL related flags
	opts.ConfigFile = opts.CollectCommand.Flag("config-file", "Path to the config file.").Default("~/.my.cnf").String()
	opts.MySQLHost = opts.CollectCommand.Flag("mysql-host", "MySQL host.").String()
	opts.MySQLPort = opts.CollectCommand.Flag("mysql-port", "MySQL port.").Int()
	opts.MySQLUser = opts.CollectCommand.Flag("mysql-user", "MySQL user name.").String()
	opts.MySQLPass = opts.CollectCommand.Flag("mysql-password", "MySQL password.").String()
	opts.AskMySQLPass = opts.CollectCommand.Flag("ask-mysql-pass", "Ask MySQL password.").Bool()
	// Aditional flags
	opts.AdditionalCmds = opts.CollectCommand.Flag("extra-cmd",
		"Also run this command as part of the data collection. This parameter can be used more than once.").Strings()
	opts.EncryptPassword = opts.CollectCommand.Flag("encrypt-password", "Encrypt the output file using this password."+
		" If ommited, the file won't be encrypted.").String()
	// No-Flags
	opts.NoCollect = opts.CollectCommand.Flag("no-collect", "Do not collect data").Bool()
	opts.NoSanitize = opts.CollectCommand.Flag("no-sanitize", "Sanitize data").Bool()
	opts.NoEncrypt = opts.CollectCommand.Flag("no-encrypt", "Do not encrypt the output file.").Bool()
	opts.NoSanitizeHostnames = opts.CollectCommand.Flag("no-sanitize-hostnames", "Don't sanitize host names.").Bool()
	opts.NoSanitizeQueries = opts.CollectCommand.Flag("no-sanitize-queries", "Do not replace queries by their fingerprints.").Bool()
	opts.NoRemoveTempFiles = opts.CollectCommand.Flag("no-remove-temp-files", "Do not remove temporary files.").Bool()

	// Sanitize command flags
	opts.SanitizeInputFile = opts.SanitizeCommand.Flag("input-file", "Input file. If not specified, the input will be Stdin.").String()
	opts.SanitizeOutputFile = opts.SanitizeCommand.Flag("output-file", "Output file. If not specified, the input will be Stdout.").String()
	opts.DontSanitizeHostnames = opts.SanitizeCommand.Flag("no-sanitize-hostnames", "Don't sanitize host names.").Bool()
	opts.DontSanitizeQueries = opts.SanitizeCommand.Flag("no-sanitize-queries", "Don't replace queries by their fingerprints.").Bool()

	opts.Command, err = app.Parse(os.Args[1:])
	if err != nil {
		return nil, err
	}

	if *opts.Debug {
		log.SetLevel(log.DebugLevel)
	}

	*opts.BinDir = expandHomeDir(*opts.BinDir)
	*opts.ConfigFile = expandHomeDir(*opts.ConfigFile)
	*opts.TempDir = expandHomeDir(*opts.TempDir)
	for _, incDir := range *opts.IncludeDirs {
		incDir = expandHomeDir(incDir)
	}

	if *opts.BinDir != "" {
		os.Setenv("PATH", fmt.Sprintf("%s%s%s", *opts.BinDir, string(os.PathListSeparator), os.Getenv("PATH")))
	}

	lp, err := exec.LookPath("pt-summary")
	if (err != nil || lp == "") && *opts.BinDir == "" && opts.Command == "collect" && !*opts.NoCollect {
		return nil, errors.New("Cannot find Percona Toolkit binaries. Please run this tool again using --bin-dir parameter")
	}

	switch opts.Command {
	case collectCmd:
		mycnf, err := getParamsFromMyCnf(*opts.ConfigFile)
		if err == nil {
			if err = validateMySQLParams(opts, mycnf); err != nil {
				return nil, err
			}
		}
		if *opts.AskMySQLPass {
			if err = askMySQLPassword(opts); err != nil {
				return nil, err
			}
		}
		err = askEncryptionPassword(opts, true)
	case encryptCmd:
		err = askEncryptionPassword(opts, true)
	case decryptCmd:
		if !strings.HasSuffix(*opts.DecryptInFile, ".aes") && *opts.DecryptOutFile == "" {
			return nil, fmt.Errorf("Input file does not have .aes extension. I cannot infer the output file")
		}
		err = askEncryptionPassword(opts, false)
	}

	if err != nil {
		return nil, err
	}

	return opts, nil
}

func validateMySQLParams(opts *cliOptions, mycnf *myDefaults) error {
	if *opts.MySQLPort == 0 && mycnf.MySQLPort > 0 {
		log.Debugf("Setting default port from config file")
		*opts.MySQLPort = mycnf.MySQLPort
	}
	if *opts.MySQLHost == "" && mycnf.MySQLHost != "" {
		*opts.MySQLHost = mycnf.MySQLHost
		log.Debugf("Setting default host from config file")
	}
	if *opts.MySQLUser == "" && mycnf.MySQLUser != "" {
		log.Debugf("Setting default user from config file")
		*opts.MySQLUser = mycnf.MySQLUser
	}
	if *opts.MySQLPass == "" && mycnf.MySQLPass != "" {
		log.Debugf("Setting default password from config file")
		*opts.MySQLPass = mycnf.MySQLPass
	}

	if *opts.MySQLHost == "" {
		log.Debugf("MySQL host is empty. Setting it to %s", defaultMySQLHost)
		*opts.MySQLHost = defaultMySQLHost
	}
	if *opts.MySQLPort == 0 {
		log.Debugf("MySQL port is empty. Setting it to %d", defaultMySQLPort)
		*opts.MySQLPort = defaultMySQLPort
	}
	if *opts.MySQLUser == "" {
		return fmt.Errorf("MySQL user cannot be empty")
	}

	return nil
}

func askMySQLPassword(opts *cliOptions) error {
	if *opts.AskMySQLPass {
		fmt.Printf("MySQL password for user %q:", *opts.MySQLUser)
		passb, err := terminal.ReadPassword(0)
		if err != nil {
			return errors.Wrap(err, "Cannot read MySQL password from the terminal")
		}
		*opts.MySQLPass = string(passb)
	}
	return nil
}

func askEncryptionPassword(opts *cliOptions, requireConfirmation bool) error {
	if !*opts.NoEncrypt && *opts.EncryptPassword == "" {
		fmt.Print("Encryption password: ")
		passa, err := terminal.ReadPassword(0)
		if err != nil {
			return errors.Wrap(err, "Cannot read encryption password from the terminal")
		}
		fmt.Println("")
		if requireConfirmation {
			fmt.Print("Re type password: ")
			passb, err := terminal.ReadPassword(0)
			if err != nil {
				return errors.Wrap(err, "Cannot read encryption password confirmation from the terminal")
			}
			fmt.Println("")
			if string(passa) != string(passb) {
				return errors.New("Passwords don't match")
			}
		}
		*opts.EncryptPassword = string(passa)
	}
	return nil
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
