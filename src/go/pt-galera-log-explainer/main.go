package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/alecthomas/kong"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"github.com/pkg/errors"
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
	NoColor        bool
	Since          *time.Time      `help:"Only list events after this date, format: 2023-01-23T03:53:40Z (RFC3339)"`
	Until          *time.Time      `help:"Only list events before this date"`
	Verbosity      types.Verbosity `type:"counter" short:"v" default:"1" help:"-v: Detailed (default), -vv: DebugMySQL (add every mysql info the tool used), -vvv: Debug (internal tool debug)"`
	PxcOperator    bool            `default:"false" help:"Analyze logs from Percona PXC operator. Off by default because it negatively impacts performance for non-k8s setups"`
	ExcludeRegexes []string        `help:"Remove regexes from analysis. List regexes using 'pt-galera-log-explainer regex-list'"`

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

type versioncmd struct{}

func (v *versioncmd) Help() string {
	return ""
}
func (v *versioncmd) Run() error {
	fmt.Printf("version: %s, commit:%s, built at %s\n", version, commit, date)
	return nil
}

// timelineFromPaths takes every path, search them using a list of regexes
// and organize them in a timeline that will be ready to aggregate or read
func timelineFromPaths(paths []string, toCheck types.RegexMap, since, until *time.Time) (types.Timeline, error) {
	timeline := make(types.Timeline)
	found := false

	for _, path := range paths {

		extr := newExtractor(path, toCheck, since, until)

		localTimeline, err := extr.search()
		if err != nil {
			extr.logger.Warn().Err(err).Msg("Search failed")
			continue
		}
		found = true
		extr.logger.Debug().Str("path", path).Msg("Finished searching")

		// identify the node with the easiest to read information
		// this is critical part to aggregate logs: this is what enable to merge logs
		// ultimately the "identifier" will be used for columns header
		var node string
		if CLI.PxcOperator {
			node = path

		} else {

			// Why it should not just identify using the file path:
			// so that we are able to merge files that belong to the same nodes
			// we wouldn't want them to be shown as from different nodes
			node = types.Identifier(localTimeline[len(localTimeline)-1].Ctx)
			if t, ok := timeline[node]; ok {

				extr.logger.Debug().Str("path", path).Str("node", node).Msg("Merging with existing timeline")
				localTimeline = types.MergeTimeline(t, localTimeline)
			}
		}
		extr.logger.Debug().Str("path", path).Str("node", node).Msg("Storing timeline")
		timeline[node] = localTimeline

	}
	if !found {
		return nil, errors.New("Could not find data")
	}
	return timeline, nil
}

// extractor is an utility struct to store what needs to be done
type extractor struct {
	regexes      types.RegexMap
	path         string
	since, until *time.Time
	logger       zerolog.Logger
}

func newExtractor(path string, toCheck types.RegexMap, since, until *time.Time) extractor {
	e := extractor{regexes: toCheck, path: path, since: since, until: until}
	e.logger = log.With().Str("component", "extractor").Str("path", e.path).Logger()
	if since != nil {
		e.logger = e.logger.With().Time("since", *e.since).Logger()
	}
	if until != nil {
		e.logger = e.logger.With().Time("until", *e.until).Logger()
	}
	e.logger.Debug().Msg("new extractor")

	return e
}

func (e *extractor) grepArgument() string {

	regexToSendSlice := e.regexes.Compile()

	grepRegex := "^"
	if CLI.PxcOperator {
		// special case
		// I'm not adding pxcoperator map the same way others are used, because they do not have the same formats and same place
		// it needs to be put on the front so that it's not 'merged' with the '{"log":"' json prefix
		// this is to keep things as close as '^' as possible to keep doing prefix searches
		grepRegex += "((" + strings.Join(regex.PXCOperatorMap.Compile(), "|") + ")|^{\"log\":\""
		e.regexes.Merge(regex.PXCOperatorMap)
	}
	if e.since != nil {
		grepRegex += "(" + regex.BetweenDateRegex(e.since, CLI.PxcOperator) + "|" + regex.NoDatesRegex(CLI.PxcOperator) + ")"
	}
	grepRegex += ".*"
	grepRegex += "(" + strings.Join(regexToSendSlice, "|") + ")"
	if CLI.PxcOperator {
		grepRegex += ")"
	}
	e.logger.Debug().Str("grepArg", grepRegex).Msg("Compiled grep arguments")
	return grepRegex
}

// search is the main function to search what we want in a file
func (e *extractor) search() (types.LocalTimeline, error) {

	// A first pass is done, with every regexes we want compiled in a single one.
	grepRegex := e.grepArgument()

	/*
		Regular grep is actually used

		There are no great alternatives, even less as golang libraries.
		grep itself do not have great alternatives: they are less performant for common use-cases, or are not easily portable, or are costlier to execute.
		grep is everywhere, grep is good enough, it even enable to use the stdout pipe.

		The usual bottleneck with grep is that it is single-threaded, but we actually benefit
		from a sequential scan here as we will rely on the log order.

		Also, being sequential also ensure this program is light enough to run without too much impacts
		It also helps to be transparent and not provide an obscure tool that work as a blackbox
	*/
	if runtime.GOOS == "darwin" && CLI.GrepCmd == "grep" {
		e.logger.Warn().Msg("On Darwin systems, use 'pt-galera-log-explainer --grep-cmd=ggrep' as it requires grep v3")
	}

	cmd := exec.Command(CLI.GrepCmd, CLI.GrepArgs, grepRegex, e.path)

	out, _ := cmd.StdoutPipe()
	defer out.Close()

	err := cmd.Start()
	if err != nil {
		return nil, errors.Wrapf(err, "failed to search in %s", e.path)
	}

	// grep treatment
	s := bufio.NewScanner(out)

	// it will iterate on stdout pipe results
	lt, err := e.iterateOnResults(s)
	if err != nil {
		e.logger.Warn().Err(err).Msg("Failed to iterate on results")
	}

	// double-check it stopped correctly
	if err = cmd.Wait(); err != nil {
		if exiterr, ok := err.(*exec.ExitError); ok && exiterr.ExitCode() == 1 {
			return nil, errors.New("Found nothing")
		}
		return nil, errors.Wrap(err, "grep subprocess error")
	}

	if len(lt) == 0 {
		return nil, errors.New("Found nothing")
	}

	return lt, nil
}

func (e *extractor) sanitizeLine(s string) string {
	if len(s) > 0 && s[0] == '\t' {
		return s[1:]
	}
	return s
}

// iterateOnResults will take line by line each logs that matched regex
// it will iterate on every regexes in slice, and apply the handler for each
// it also filters out --since and --until rows
func (e *extractor) iterateOnResults(s *bufio.Scanner) ([]types.LogInfo, error) {

	var (
		line         string
		lt           types.LocalTimeline
		recentEnough bool
		displayer    types.LogDisplayer
	)
	ctx := types.NewLogCtx()
	ctx.FilePath = e.path

	for s.Scan() {
		line = e.sanitizeLine(s.Text())

		var date *types.Date
		t, layout, ok := regex.SearchDateFromLog(line)
		if ok {
			d := types.NewDate(t, layout)
			date = &d
		}

		// If it's recentEnough, it means we already validated a log: every next logs necessarily happened later
		// this is useful because not every logs have a date attached, and some without date are very useful
		if !recentEnough && e.since != nil && (date == nil || (date != nil && e.since.After(date.Time))) {
			continue
		}
		if e.until != nil && date != nil && e.until.Before(date.Time) {
			return lt, nil
		}
		recentEnough = true

		filetype := regex.FileType(line, CLI.PxcOperator)
		ctx.FileType = filetype

		// We have to find again what regex worked to get this log line
		// it can match multiple regexes
		for key, regex := range e.regexes {
			if !regex.Regex.MatchString(line) || utils.SliceContains(CLI.ExcludeRegexes, key) {
				continue
			}
			ctx, displayer = regex.Handle(ctx, line)
			li := types.NewLogInfo(date, displayer, line, regex, key, ctx, filetype)

			lt = lt.Add(li)
		}

	}
	return lt, nil
}
