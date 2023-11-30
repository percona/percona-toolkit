package display

import (
	"testing"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

func TestTransitionSeparator(t *testing.T) {
	t.Parallel()
	tests := []struct {
		keys                []string
		oldlogCtxs, logCtxs map[string]types.LogCtx
		expectedOut         string
		name                string
	}{
		{
			name: "no changes",
			keys: []string{"node0", "node1"},
			oldlogCtxs: map[string]types.LogCtx{
				"node0": {},
				"node1": {},
			},
			logCtxs: map[string]types.LogCtx{

				"node0": {},
				"node1": {},
			},
			expectedOut: "",
		},
		{
			name: "filepath changed on node0",
			keys: []string{"node0", "node1"},
			oldlogCtxs: map[string]types.LogCtx{
				"node0": {FilePath: "path1"},
				"node1": {},
			},
			logCtxs: map[string]types.LogCtx{

				"node0": {FilePath: "path2"},
				"node1": {},
			},
			/*
				path1
				(file path)
				 V
				path2
			*/
			expectedOut: "\tpath1\t\t\n\t(file path)\t\t\n\t V \t\t\n\tpath2\t\t",
		},
		{
			name: "filepath changed on node1",
			keys: []string{"node0", "node1"},
			oldlogCtxs: map[string]types.LogCtx{
				"node0": {},
				"node1": {FilePath: "path1"},
			},
			logCtxs: map[string]types.LogCtx{

				"node0": {},
				"node1": {FilePath: "path2"},
			},
			expectedOut: "\t\tpath1\t\n\t\t(file path)\t\n\t\t V \t\n\t\tpath2\t",
		},
		{
			name: "filepath changed on both",
			keys: []string{"node0", "node1"},
			oldlogCtxs: map[string]types.LogCtx{
				"node0": {FilePath: "path1_0"},
				"node1": {FilePath: "path1_1"},
			},
			logCtxs: map[string]types.LogCtx{
				"node0": {FilePath: "path2_0"},
				"node1": {FilePath: "path2_1"},
			},
			expectedOut: "\tpath1_0\tpath1_1\t\n\t(file path)\t(file path)\t\n\t V \t V \t\n\tpath2_0\tpath2_1\t",
		},
		{
			name: "node name changed on node1",
			keys: []string{"node0", "node1"},
			oldlogCtxs: map[string]types.LogCtx{
				"node0": {},
				"node1": {OwnNames: []string{"name1"}},
			},
			logCtxs: map[string]types.LogCtx{
				"node0": {},
				"node1": {OwnNames: []string{"name1", "name2"}},
			},
			expectedOut: "\t\tname1\t\n\t\t(node name)\t\n\t\t V \t\n\t\tname2\t",
		},
		{
			name: "node ip changed on node1",
			keys: []string{"node0", "node1"},
			oldlogCtxs: map[string]types.LogCtx{
				"node0": {},
				"node1": {OwnIPs: []string{"ip1"}},
			},
			logCtxs: map[string]types.LogCtx{
				"node0": {},
				"node1": {OwnIPs: []string{"ip1", "ip2"}},
			},
			expectedOut: "\t\tip1\t\n\t\t(node ip)\t\n\t\t V \t\n\t\tip2\t",
		},
		{
			name: "version changed on node1",
			keys: []string{"node0", "node1"},
			oldlogCtxs: map[string]types.LogCtx{
				"node0": {},
				"node1": {Version: "8.0.28"},
			},
			logCtxs: map[string]types.LogCtx{
				"node0": {},
				"node1": {Version: "8.0.30"},
			},
			expectedOut: "\t\t8.0.28\t\n\t\t(version)\t\n\t\t V \t\n\t\t8.0.30\t",
		},
		{
			name: "node ip, node name and filepath changed on node1", // very possible with operators
			keys: []string{"node0", "node1"},
			oldlogCtxs: map[string]types.LogCtx{
				"node0": {},
				"node1": {OwnIPs: []string{"ip1"}, OwnNames: []string{"name1"}, FilePath: "path1"},
			},
			logCtxs: map[string]types.LogCtx{
				"node0": {},
				"node1": {OwnIPs: []string{"ip1", "ip2"}, OwnNames: []string{"name1", "name2"}, FilePath: "path2"},
			},
			/*
				(timestamp)	(node0)	(node1)
					\t		\t		path1	\t\n
					\t		\t		(file path)	\t\n
					\t		\t		 V	\t\n
					\t		\t		path2	\t\n
					\t		\t		name1	\t\n
					\t		\t		(node name)	\t\n
					\t		\t		 V	\t\n
					\t		\t		name2	\t\n
					\t		\t		ip2	\t\n
					\t		\t		(node ip)		\t\n
					\t		\t		 V	\t\n
					\t		\t		ip2	\t --only one without \n

			*/
			expectedOut: "\t\tpath1\t\n\t\t(file path)\t\n\t\t V \t\n\t\tpath2\t\n\t\tname1\t\n\t\t(node name)\t\n\t\t V \t\n\t\tname2\t\n\t\tip1\t\n\t\t(node ip)\t\n\t\t V \t\n\t\tip2\t",
		},

		{
			name: "node ip, node name and filepath changed on node1, nodename changed on node2", // very possible with operators
			keys: []string{"node0", "node1"},
			oldlogCtxs: map[string]types.LogCtx{
				"node0": {OwnNames: []string{"name1_0"}},
				"node1": {OwnIPs: []string{"ip1"}, OwnNames: []string{"name1_1"}, FilePath: "path1"},
			},
			logCtxs: map[string]types.LogCtx{
				"node0": {OwnNames: []string{"name1_0", "name2_0"}},
				"node1": {OwnIPs: []string{"ip1", "ip2"}, OwnNames: []string{"name1_1", "name2_1"}, FilePath: "path2"},
			},
			/*
				(timestamp)	(node0)			(node1)
					\t		name1_0\t		path1	\t\n
					\t		(node name)\t	(file path)	\t\n
					\t		 V \t			 V	\t\n
					\t		name2_0\t		path2	\t\n
					\t		\t				name1_1	\t\n
					\t		\t				(node name)	\t\n
					\t		\t				 V	\t\n
					\t		\t				name2_1	\t\n
					\t		\t				ip2	\t\n
					\t		\t				(node ip)		\t\n
					\t		\t				 V	\t\n
					\t		\t				ip2	\t --only one without \n

			*/
			expectedOut: "\tname1_0\tpath1\t\n\t(node name)\t(file path)\t\n\t V \t V \t\n\tname2_0\tpath2\t\n\t\tname1_1\t\n\t\t(node name)\t\n\t\t V \t\n\t\tname2_1\t\n\t\tip1\t\n\t\t(node ip)\t\n\t\t V \t\n\t\tip2\t",
		},
	}

	utils.SkipColor = true
	for _, test := range tests {
		out := transitionSeparator(test.keys, test.oldlogCtxs, test.logCtxs)
		if out != test.expectedOut {
			t.Errorf("testname: %s, expected: \n%#v\n got: \n%#v", test.name, test.expectedOut, out)
		}

	}
}
