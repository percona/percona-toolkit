package main

import (
	"fmt"
	"os"
	"time"

	"github.com/alecthomas/kong"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

// ldflags
var (
	version string
	commit  string
	date    string
)

var CLI struct {
	NoColor          bool
	Since            *time.Time      `help:"Only list events after this date, format: 2023-01-23T03:53:40Z (RFC3339)"`
	Until            *time.Time      `help:"Only list events before this date"`
	Verbosity        types.Verbosity `type:"counter" short:"v" default:"1" help:"-v: Detailed (default), -vv: DebugMySQL (add every mysql info the tool used), -vvv: Debug (internal tool debug)"`
	PxcOperator      bool            `default:"false" help:"Analyze logs from Percona PXC operator. Off by default because it negatively impacts performance for non-k8s setups"`
	ExcludeRegexes   []string        `help:"Remove regexes from analysis. List regexes using 'pt-galera-log-explainer regex-list'"`
	MergeByDirectory bool            `help:"Instead of relying on identification, merge contexts and columns by base directory. Very useful when dealing with many small logs organized per directories."`

	List      list       `cmd:""`
	Whois     whois      `cmd:""`
	Sed       sed        `cmd:""`
	Ctx       ctx        `cmd:""`
	RegexList regexList  `cmd:""`
	Version   versioncmd `cmd:""`
	Conflicts conflicts  `cmd:""`

	GrepCmd  string `help:"'grep' command path. Could need to be set to 'ggrep' for darwin systems" default:"grep"`
	GrepArgs string `help:"'grep' arguments. perl regexp (-P) is necessary. -o will break the tool" default:"-P"`
}

type versioncmd struct{}

func (v *versioncmd) Help() string {
	return ""
}
func (v *versioncmd) Run() error {
	fmt.Printf("version: %s, commit:%s, built at %s\n", version, commit, date)
	return nil
}

func main() {
	ctx := kong.Parse(&CLI,
		kong.Name("pt-galera-log-explainer"),
		kong.Description("An utility to merge and help analyzing Galera logs"),
		kong.UsageOnError(),
	)

	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	zerolog.SetGlobalLevel(zerolog.WarnLevel)
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})
	if CLI.Verbosity == types.Debug {
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	}

	utils.SkipColor = CLI.NoColor
	err := ctx.Run()
	ctx.FatalIfErrorf(err)
}
