package main

import (
	"bufio"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"github.com/pkg/errors"
	"github.com/rs/zerolog/log"
)

var logger = log.With().Str("component", "extractor").Logger()

func init() {

	if CLI.Since != nil {
		logger = logger.With().Time("since", *CLI.Since).Logger()
	}
	if CLI.Until != nil {
		logger = logger.With().Time("until", *CLI.Until).Logger()
	}
}

var (
	errDirectoriesUnsupported = errors.New("directories are not supported")
)

// timelineFromPaths takes every path, search them using a list of regexes
// and organize them in a timeline that will be ready to aggregate or read
func timelineFromPaths(paths []string, regexes types.RegexMap) (types.Timeline, error) {
	timeline := make(types.Timeline)
	found := false

	compiledRegex := prepareGrepArgument(regexes)

	for _, path := range paths {
		osinfo, err := os.Stat(path)
		if err != nil {
			return nil, err
		}
		if osinfo.IsDir() {
			return nil, errDirectoriesUnsupported
		}

		stdout := make(chan string)

		go func() {
			err := execGrepAndIterate(path, compiledRegex, stdout)
			if err != nil {
				logger.Error().Str("path", path).Err(err).Msg("execGrepAndIterate returned error")
			}
			close(stdout)
		}()

		// it will iterate on stdout pipe results
		localTimeline := iterateOnGrepResults(path, regexes, stdout)
		if len(localTimeline) == 0 {
			continue
		}
		found = true
		logger.Debug().Str("path", path).Msg("finished searching")

		// Why it should not just identify using the file path:
		// so that we are able to merge files that belong to the same nodes
		// we wouldn't want them to be shown as from different nodes
		if CLI.PxcOperator || CLI.SkipMerge {
			timeline[path] = localTimeline
		} else if CLI.MergeByDirectory {
			timeline.MergeByDirectory(path, localTimeline)
		} else {
			timeline.MergeByIdentifier(localTimeline)
		}
	}
	if !found {
		return nil, errors.New("could not find data")
	}
	return timeline, nil
}

func prepareGrepArgument(regexes types.RegexMap) string {

	regexToSendSlice := regexes.Compile()

	grepRegex := "^"
	if CLI.PxcOperator {
		// special case
		// I'm not adding pxcoperator map the same way others are used, because they do not have the same formats and same place
		// it needs to be put on the front so that it's not 'merged' with the '{"log":"' json prefix
		// this is to keep things as close as '^' as possible to keep doing prefix searches
		grepRegex += "((" + strings.Join(regex.PXCOperatorMap.Compile(), "|") + ")|^{\"log\":\""
		regexes.Merge(regex.PXCOperatorMap)
	}
	if CLI.Since != nil {
		grepRegex += "(" + regex.BetweenDateRegex(CLI.Since, CLI.PxcOperator) + "|" + regex.NoDatesRegex(CLI.PxcOperator) + ")"
	}
	grepRegex += ".*"
	grepRegex += "(" + strings.Join(regexToSendSlice, "|") + ")"
	if CLI.PxcOperator {
		grepRegex += ")"
	}
	logger.Debug().Str("grepArg", grepRegex).Msg("compiled grep arguments")
	return grepRegex
}

func execGrepAndIterate(path, compiledRegex string, stdout chan<- string) error {

	// A first pass is done, with every regexes we want compiled in a single one.

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
		logger.Warn().Msg("On Darwin systems, use 'pt-galera-log-explainer --grep-cmd=ggrep' as it requires grep v3")
	}

	cmd := exec.Command(CLI.GrepCmd, "-a", "-P", compiledRegex, path)

	out, err := cmd.StdoutPipe()
	if err != nil {
		return errors.Wrap(err, "could not open stdout pipe")
	}
	defer out.Close()

	err = cmd.Start()
	if err != nil {
		return errors.Wrapf(err, "failed to search in %s", path)
	}

	// grep treatment
	s := bufio.NewScanner(out)
	for s.Scan() {
		stdout <- s.Text()
	}

	// double-check it stopped correctly
	if err = cmd.Wait(); err != nil {
		if exiterr, ok := err.(*exec.ExitError); ok && exiterr.ExitCode() == 1 {
			return nil
		}
		return errors.Wrap(err, "grep subprocess error")
	}

	return nil
}

func sanitizeLine(s string) string {
	if len(s) > 0 && s[0] == '\t' {
		return s[1:]
	}
	return s
}

// iterateOnGrepResults will take line by line each logs that matched regex
// it will iterate on every regexes in slice, and apply the handler for each
// it also filters out --since and --until rows
func iterateOnGrepResults(path string, regexes types.RegexMap, grepStdout <-chan string) types.LocalTimeline {

	var (
		lt        types.LocalTimeline
		displayer types.LogDisplayer
		timestamp time.Time
	)
	logCtx := types.NewLogCtx()
	logCtx.FilePath = path

	for line := range grepStdout {
		line = sanitizeLine(line)

		var date *types.Date
		t, layout, ok := regex.SearchDateFromLog(line)
		if ok {
			// diff between date and timestamp:
			// timestamp is an internal usage to handle translations, it must be non-empty
			// date is something that will be displayed ultimately, it can empty
			date = types.NewDate(t, layout)
			timestamp = t
		} // else, keep the previous timestamp

		// If it's recentEnough, it means we already validated a log: every next logs necessarily happened later
		// this is useful because not every logs have a date attached, and some without date are very useful
		if CLI.Since != nil && CLI.Since.After(timestamp) {
			continue
		}
		if CLI.Until != nil && CLI.Until.Before(timestamp) {
			return lt
		}

		filetype := regex.FileType(line, CLI.PxcOperator)
		logCtx.FileType = filetype

		// We have to find again what regex worked to get this log line
		// it can match multiple regexes
		for key, regex := range regexes {
			if !regex.Regex.MatchString(line) || utils.SliceContains(CLI.ExcludeRegexes, key) {
				continue
			}
			logCtx, displayer = regex.Handle(logCtx, line, timestamp)
			li := types.NewLogInfo(date, displayer, line, regex, key, logCtx, filetype)
			lt = lt.Add(li)
		}

	}
	return lt
}
