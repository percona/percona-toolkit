package display

import (
	"fmt"
	"log"
	"os"
	"sort"
	"strings"

	// regular tabwriter do not work with color, this is a forked versions that ignores color special characters
	"github.com/Ladicle/tabwriter"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

// TimelineCLI print a timeline to the terminal using tabulated format
// It will print header and footers, and dequeue the timeline chronologically
func TimelineCLI(timeline types.Timeline, verbosity types.Verbosity) {

	timeline = removeEmptyColumns(timeline, verbosity)

	// to hold the current context for each node
	// "keys" is needed, because iterating over a map must give a different order each time
	// a slice keeps its order
	keys, currentContext := initKeysContext(timeline)           // currentcontext to follow when important thing changed
	latestContext := timeline.GetLatestUpdatedContextsByNodes() // so that we have fully updated context when we print
	lastContext := map[string]types.LogCtx{}                    // just to follow when important thing changed

	w := tabwriter.NewWriter(os.Stdout, 8, 8, 3, ' ', tabwriter.DiscardEmptyColumns)
	defer w.Flush()

	// header
	fmt.Fprintln(w, headerNodes(keys))
	fmt.Fprintln(w, headerFilePath(keys, currentContext))
	fmt.Fprintln(w, headerIP(keys, latestContext))
	fmt.Fprintln(w, headerName(keys, latestContext))
	fmt.Fprintln(w, headerVersion(keys, latestContext))
	fmt.Fprintln(w, separator(keys))

	var (
		args      []string // stuff to print
		linecount int
	)

	// as long as there is a next event to print
	for nextNodes := timeline.IterateNode(); len(nextNodes) != 0; nextNodes = timeline.IterateNode() {

		// Date column
		date := timeline[nextNodes[0]][0].Date
		args = []string{""}
		if date != nil {
			args = []string{date.DisplayTime}
		}

		displayedValue := 0

		// node values
		for _, node := range keys {

			if !utils.SliceContains(nextNodes, node) {
				// if there are no events, having a | is needed for tabwriter
				// A few color can also help highlighting how the node is doing
				ctx := currentContext[node]
				args = append(args, utils.PaintForState("| ", ctx.State()))
				continue
			}
			loginfo := timeline[node][0]
			lastContext[node] = currentContext[node]
			currentContext[node] = loginfo.Ctx

			timeline.Dequeue(node)

			msg := loginfo.Msg(latestContext[node])
			if verbosity > loginfo.Verbosity && msg != "" {
				args = append(args, msg)
				displayedValue++
			} else {
				args = append(args, utils.PaintForState("| ", loginfo.Ctx.State()))
			}
		}

		if sep := transitionSeparator(keys, lastContext, currentContext); sep != "" {
			// reset current context, so that we avoid duplicating transitions
			// lastContext/currentContext is only useful for that anyway
			lastContext = map[string]types.LogCtx{}
			for k, v := range currentContext {
				lastContext[k] = v
			}
			// print transition
			fmt.Fprintln(w, sep)
		}

		// If line is not filled with default placeholder values
		if displayedValue == 0 {
			continue

		}

		// Print tabwriter line
		_, err := fmt.Fprintln(w, strings.Join(args, "\t")+"\t")
		if err != nil {
			log.Println("Failed to write a line", err)
		}
		linecount++
	}

	// footer
	// only having a header is not fast enough to read when there are too many lines
	if linecount >= 50 {
		fmt.Fprintln(w, separator(keys))
		fmt.Fprintln(w, headerNodes(keys))
		fmt.Fprintln(w, headerFilePath(keys, currentContext))
		fmt.Fprintln(w, headerIP(keys, currentContext))
		fmt.Fprintln(w, headerName(keys, currentContext))
		fmt.Fprintln(w, headerVersion(keys, currentContext))
	}

	// TODO: where to print conflicts details ?
}

func initKeysContext(timeline types.Timeline) ([]string, map[string]types.LogCtx) {
	currentContext := map[string]types.LogCtx{}

	// keys will be used to access the timeline map with an ordered manner
	// without this, we would not print on the correct column as the order of a map is guaranteed to be random each time
	keys := make([]string, 0, len(timeline))
	for node := range timeline {
		keys = append(keys, node)
		if len(timeline[node]) > 0 {
			currentContext[node] = timeline[node][0].Ctx
		} else {
			// Avoid crashing, but not ideal: we could have a better default Ctx with filepath at least
			currentContext[node] = types.NewLogCtx()
		}
	}
	sort.Strings(keys)
	return keys, currentContext
}

func separator(keys []string) string {
	return " \t" + strings.Repeat(" \t", len(keys))
}

func headerNodes(keys []string) string {
	return "identifier\t" + strings.Join(keys, "\t") + "\t"
}

func headerFilePath(keys []string, ctxs map[string]types.LogCtx) string {
	header := "current path\t"
	for _, node := range keys {
		if ctx, ok := ctxs[node]; ok {
			if len(ctx.FilePath) < 50 {
				header += ctx.FilePath + "\t"
			} else {
				header += "..." + ctx.FilePath[len(ctx.FilePath)-50:] + "\t"
			}
		} else {
			header += " \t"
		}
	}
	return header
}

func headerIP(keys []string, ctxs map[string]types.LogCtx) string {
	header := "last known ip\t"
	for _, node := range keys {
		if ctx, ok := ctxs[node]; ok && len(ctx.OwnIPs) > 0 {
			header += ctx.OwnIPs[len(ctx.OwnIPs)-1] + "\t"
		} else {
			header += " \t"
		}
	}
	return header
}

func headerVersion(keys []string, ctxs map[string]types.LogCtx) string {
	header := "mysql version\t"
	for _, node := range keys {
		if ctx, ok := ctxs[node]; ok {
			header += ctx.Version + "\t"
		}
	}
	return header
}

func headerName(keys []string, ctxs map[string]types.LogCtx) string {
	header := "last known name\t"
	for _, node := range keys {
		if ctx, ok := ctxs[node]; ok && len(ctx.OwnNames) > 0 {
			header += ctx.OwnNames[len(ctx.OwnNames)-1] + "\t"
		} else {
			header += " \t"
		}
	}
	return header
}

func removeEmptyColumns(timeline types.Timeline, verbosity types.Verbosity) types.Timeline {

	for key := range timeline {
		if !timeline[key][len(timeline[key])-1].Ctx.HasVisibleEvents(verbosity) {
			delete(timeline, key)
		}
	}
	return timeline
}

// transition is to builds the check+display of an important context transition
// like files, IP, name, anything
// summary will hold the whole multi-line report
type transition struct {
	s1, s2, changeType string
	ok                 bool
	summary            transitionSummary
}

// transitions will hold any number of transition to test
// transitionToPrint will hold whatever transition happened, but will also store empty transitions
// to ensure that every columns will have the same amount of rows to write: this is needed to maintain
// the columnar output
type transitions struct {
	tests             []*transition
	transitionToPrint []*transition
	numberFound       int
}

// 4 here means there are 4 rows to store
// 0: base info, 1: type of info that changed, 2: just an arrow placeholder, 3: new info
const RowPerTransitions = 4

type transitionSummary [RowPerTransitions]string

// because only those transitions are implemented: file path, ip, node name, version
const NumberOfPossibleTransition = 4

// transactionSeparator is useful to highligh a change of context
// example, changing file
//   mysqld.log.2
//    (file path)
//           V
//   mysqld.log.1
// or a change of ip, node name, ...
// This feels complicated: it is
// It was made difficult because of how "tabwriter" works
// it needs an element on each columns so that we don't break columns
// The rows can't have a variable count of elements: it has to be strictly identical each time
// so the whole next functions are here to ensure it takes minimal spaces, while giving context and preserving columns
func transitionSeparator(keys []string, oldctxs, ctxs map[string]types.LogCtx) string {

	ts := map[string]*transitions{}

	// For each columns to print, we build tests
	for _, node := range keys {
		ctx, ok1 := ctxs[node]
		oldctx, ok2 := oldctxs[node]

		ts[node] = &transitions{tests: []*transition{}}
		if ok1 && ok2 {
			ts[node].tests = append(ts[node].tests, &transition{s1: oldctx.FilePath, s2: ctx.FilePath, changeType: "file path"})

			if len(oldctx.OwnNames) > 0 && len(ctx.OwnNames) > 0 {
				ts[node].tests = append(ts[node].tests, &transition{s1: oldctx.OwnNames[len(oldctx.OwnNames)-1], s2: ctx.OwnNames[len(ctx.OwnNames)-1], changeType: "node name"})
			}
			if len(oldctx.OwnIPs) > 0 && len(ctx.OwnIPs) > 0 {
				ts[node].tests = append(ts[node].tests, &transition{s1: oldctx.OwnIPs[len(oldctx.OwnIPs)-1], s2: ctx.OwnIPs[len(ctx.OwnIPs)-1], changeType: "node ip"})
			}
			if oldctx.Version != "" && ctx.Version != "" {
				ts[node].tests = append(ts[node].tests, &transition{s1: oldctx.Version, s2: ctx.Version, changeType: "version"})
			}

		}

		// we resolve tests
		ts[node].fillEmptyTransition()
		ts[node].iterate()
	}

	highestStackOfTransitions := 0

	// we need to know the maximum height to print
	for _, node := range keys {
		if ts[node].numberFound > highestStackOfTransitions {
			highestStackOfTransitions = ts[node].numberFound
		}
	}
	// now we have the height, we compile the stack to print (possibly empty placeholders for some columns)
	for _, node := range keys {
		ts[node].stackPrioritizeFound(highestStackOfTransitions)
	}

	out := "\t"
	for i := 0; i < highestStackOfTransitions; i++ {
		for row := 0; row < RowPerTransitions; row++ {
			for _, node := range keys {
				out += ts[node].transitionToPrint[i].summary[row]
			}
			if !(i == highestStackOfTransitions-1 && row == RowPerTransitions-1) { // unless last row
				out += "\n\t"
			}
		}
	}

	if out == "\t" {
		return ""
	}
	return out
}

func (ts *transitions) iterate() {

	for _, test := range ts.tests {

		test.summarizeIfDifferent()
		if test.ok {
			ts.numberFound++
		}
	}

}

func (ts *transitions) stackPrioritizeFound(height int) {
	for i, test := range ts.tests {
		// if at the right height
		if len(ts.tests)-i+len(ts.transitionToPrint) == height {
			ts.transitionToPrint = append(ts.transitionToPrint, ts.tests[i:]...)
		}
		if test.ok {
			ts.transitionToPrint = append(ts.transitionToPrint, test)
		}
	}
}

func (ts *transitions) fillEmptyTransition() {
	if len(ts.tests) == NumberOfPossibleTransition {
		return
	}
	for i := len(ts.tests); i < NumberOfPossibleTransition; i++ {
		ts.tests = append(ts.tests, &transition{s1: "", s2: "", changeType: ""})
	}

}

func (t *transition) summarizeIfDifferent() {
	if t.s1 != t.s2 {
		t.summary = [RowPerTransitions]string{utils.Paint(utils.BrightBlueText, t.s1), utils.Paint(utils.BlueText, "("+t.changeType+")"), utils.Paint(utils.BrightBlueText, " V "), utils.Paint(utils.BrightBlueText, t.s2)}
		t.ok = true
	}
	for i := range t.summary {
		t.summary[i] = t.summary[i] + "\t"
	}
	return
}
