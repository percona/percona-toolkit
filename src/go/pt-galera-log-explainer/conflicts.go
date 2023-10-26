package main

import (
	"encoding/json"
	"fmt"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
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

		if c.Yaml {
			tmp, err := yaml.Marshal(ctx.Conflicts)
			if err != nil {
				return err
			}
			out = string(tmp)
		} else if c.Json {
			tmp, err := json.Marshal(ctx.Conflicts)
			if err != nil {
				return err
			}
			out = string(tmp)
		} else {

			for _, conflict := range ctx.Conflicts {
				out += "\n"
				out += "\n" + utils.Paint(utils.BlueText, "seqno: ") + conflict.Seqno
				out += "\n\t" + utils.Paint(utils.BlueText, "winner: ") + conflict.Winner
				out += "\n\t" + utils.Paint(utils.BlueText, "votes per nodes:")
				for node, vote := range conflict.VotePerNode {
					displayVote := utils.Paint(utils.RedText, vote.MD5)
					if vote.MD5 == conflict.Winner {
						displayVote = utils.Paint(utils.GreenText, vote.MD5)
					}
					out += "\n\t\t" + utils.Paint(utils.BlueText, node) + ": (" + displayVote + ") " + vote.Error
				}
				out += "\n\t" + utils.Paint(utils.BlueText, "initiated by: ") + fmt.Sprintf("%v", conflict.InitiatedBy)
			}

		}
		fmt.Println(out)
		return nil
	}

	return nil
}
