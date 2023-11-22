package main

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"golang.org/x/exp/slices"
	"gopkg.in/yaml.v2"
)

type conflicts struct {
	Paths []string `arg:"" name:"paths" help:"paths of the log to use"`
	Yaml  bool     `xor:"format"`
	Json  bool     `xor:"format"`
}

func (c *conflicts) Help() string {
	return "Summarize every replication conflicts, from every node's point of view"
}

func (c *conflicts) Run() error {

	regexes := regex.IdentsMap.Merge(regex.ApplicativeMap)
	timeline, err := timelineFromPaths(c.Paths, regexes)
	if err != nil {
		return err
	}

	ctxs := timeline.GetLatestContextsByNodes()
	for _, ctx := range ctxs {
		if len(ctx.Conflicts) == 0 {
			continue
		}
		var out string

		switch {
		case c.Yaml:
			tmp, err := yaml.Marshal(ctx.Conflicts)
			if err != nil {
				return err
			}
			out = string(tmp)
		case c.Json:
			tmp, err := json.Marshal(ctx.Conflicts)
			if err != nil {
				return err
			}
			out = string(tmp)

		default:
			var b strings.Builder
			for _, conflict := range ctx.Conflicts {
				b.WriteString("\n\n")
				b.WriteString(utils.Paint(utils.BlueText, "seqno: "))
				b.WriteString(conflict.Seqno)
				b.WriteString("\n\t")
				b.WriteString(utils.Paint(utils.BlueText, "winner: "))
				b.WriteString(conflict.Winner)
				b.WriteString("\n\t")
				b.WriteString(utils.Paint(utils.BlueText, "votes per nodes:"))

				nodes := []string{}
				for node := range conflict.VotePerNode {
					nodes = append(nodes, node)
				}
				// do not iterate over VotePerNode map
				// map accesses are random, it will make regression tests harder
				slices.Sort(nodes)

				for _, node := range nodes {
					vote := conflict.VotePerNode[node]
					displayVote := utils.Paint(utils.RedText, vote.MD5)
					if vote.MD5 == conflict.Winner {
						displayVote = utils.Paint(utils.GreenText, vote.MD5)
					}
					b.WriteString("\n\t\t")
					b.WriteString(utils.Paint(utils.BlueText, node))
					b.WriteString(": (")
					b.WriteString(displayVote)
					b.WriteString(") ")
					b.WriteString(vote.Error)
				}
				b.WriteString("\n\t")
				b.WriteString(utils.Paint(utils.BlueText, "initiated by: "))
				b.WriteString(fmt.Sprintf("%v", conflict.InitiatedBy))
				out = b.String()[2:]
			}

		}
		fmt.Println(out)
		return nil
	}

	return nil
}
