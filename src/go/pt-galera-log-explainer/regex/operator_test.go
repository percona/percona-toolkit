package regex

import (
	"testing"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
)

func TestPXCOperatorRegex(t *testing.T) {
	tests := []regexTest{

		{
			log: "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] ================================================\\nView:\\n  id: 9f191762-2542-11ee-89be-13bdb1218f0e:9375811\\n  status: primary\\n  protocol_version: 4\\n  capabilities: MULTI-MASTER, CERTIFICATION, PARALLEL_APPLYING, REPLAY, ISOLATION, PAUSE, CAUSAL_READ, INCREMENTAL_WS, UNORDERED, PREORDERED, STREAMING, NBO\\n  final: no\\n  own_index: 0\\n  members(3):\\n\\t0: 45406e8d-2de0-11ee-95fc-f29a5fdf1ee0, cluster1-0\\n\\t1: 5bf18376-2de0-11ee-8333-6e755a3456ca, cluster1-2\\n\\t2: 66e2b7bf-2de0-11ee-8000-f7d68b5cf6f6, cluster1-1\\n=================================================\\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			input: regexTestState{
				LogCtx: types.LogCtx{
					OwnHashes: []string{},
					OwnNames:  []string{},
				},
				HashToNodeNames: map[string]string{},
				State:           "PRIMARY",
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "0",
					MemberCount: 3,
					OwnHashes:   []string{"45406e8d-95fc"},
					OwnNames:    []string{"cluster1-0"},
				},
				HashToNodeNames: map[string]string{"45406e8d-95fc": "cluster1-0", "5bf18376-8333": "cluster1-2", "66e2b7bf-8000": "cluster1-1"},
				State:           "PRIMARY",
			},
			expectedOut: "view member count: 3; 45406e8d-95fc is cluster1-0; 5bf18376-8333 is cluster1-2; 66e2b7bf-8000 is cluster1-1; ",
			key:         "RegexOperatorMemberAssociations",
		},

		{
			log: "+ NODE_NAME=cluster1-pxc-0.cluster1-pxc.test-percona.svc.cluster.local",
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"cluster1-pxc-0"}},
			},
			expectedOut: "local name:cluster1-pxc-0",
			key:         "RegexNodeNameFromEnv",
		},

		{
			log: "+ NODE_IP=172.17.0.2",
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnIPs: []string{"172.17.0.2"}},
			},
			expectedOut: "local ip:172.17.0.2",
			key:         "RegexNodeIPFromEnv",
		},

		{
			log:         "{\"log\":\"2023-07-05T08:17:23.447015Z 0 [Note] [MY-000000] [Galera] GCache::RingBuffer initial scan...  0.0% (         0/1073741848 bytes) complete.\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			expectedOut: "recovering gcache",
			key:         "RegexGcacheScan",
		},
	}

	iterateRegexTest(t, PXCOperatorMap, tests)
}
