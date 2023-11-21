package regex

import (
	"testing"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
)

func TestViewsRegex(t *testing.T) {
	tests := []regexTest{

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] (60205de0-8884, 'ssl://0.0.0.0:4567') connection established to 5873acd0-baa8 ssl://172.17.0.2:4567",
			input: regexTestState{
				HashToIP: map[string]string{},
			},
			expected: regexTestState{
				HashToIP: map[string]string{"5873acd0-baa8": "172.17.0.2"},
			},
			expectedOut: "172.17.0.2 established",
			key:         "RegexNodeEstablished",
		},
		{
			name: "established to node's own ip",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] (60205de0-8884, 'ssl://0.0.0.0:4567') connection established to 5873acd0-baa8 ssl://172.17.0.2:4567",
			input: regexTestState{
				Ctx: types.LogCtx{
					OwnIPs: []string{"172.17.0.2"},
				},
				HashToIP: map[string]string{},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					OwnIPs: []string{"172.17.0.2"},
				},
				HashToIP: map[string]string{"5873acd0-baa8": "172.17.0.2"},
			},
			expectedOut:          "",
			displayerExpectedNil: true,
			key:                  "RegexNodeEstablished",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] declaring 5873acd0-baa8 at ssl://172.17.0.2:4567 stable",
			input: regexTestState{
				HashToIP:    map[string]string{},
				IPToMethods: map[string]string{},
			},
			expected: regexTestState{
				HashToIP:    map[string]string{"5873acd0-baa8": "172.17.0.2"},
				IPToMethods: map[string]string{"172.17.0.2": "ssl"},
			},
			expectedOut: "172.17.0.2 joined",
			key:         "RegexNodeJoined",
		},
		{
			name: "mariadb variation",
			log:  "2001-01-01  1:01:30 0 [Note] WSREP: declaring 5873acd0-baa8 at tcp://172.17.0.2:4567 stable",
			input: regexTestState{
				HashToIP:    map[string]string{},
				IPToMethods: map[string]string{},
			},
			expected: regexTestState{
				HashToIP:    map[string]string{"5873acd0-baa8": "172.17.0.2"},
				IPToMethods: map[string]string{"172.17.0.2": "tcp"},
			},
			expectedOut: "172.17.0.2 joined",
			key:         "RegexNodeJoined",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] forgetting 871c35de-99ae (ssl://172.17.0.2:4567)",
			expectedOut: "172.17.0.2 left",
			key:         "RegexNodeLeft",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: New COMPONENT: primary = yes, bootstrap = no, my_idx = 0, memb_num = 2",
			expected: regexTestState{
				Ctx:   types.LogCtx{MemberCount: 2},
				State: "PRIMARY",
			},
			expectedOut: "PRIMARY(n=2)",
			key:         "RegexNewComponent",
		},
		{
			name: "bootstrap",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: New COMPONENT: primary = yes, bootstrap = yes, my_idx = 0, memb_num = 2",
			expected: regexTestState{
				Ctx:   types.LogCtx{MemberCount: 2},
				State: "PRIMARY",
			},
			expectedOut: "PRIMARY(n=2),bootstrap",
			key:         "RegexNewComponent",
		},
		{
			name: "don't set primary",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: New COMPONENT: primary = yes, bootstrap = no, my_idx = 0, memb_num = 2",
			input: regexTestState{
				State: "JOINER",
			},
			expected: regexTestState{
				Ctx:   types.LogCtx{MemberCount: 2},
				State: "JOINER",
			},
			expectedOut: "PRIMARY(n=2)",
			key:         "RegexNewComponent",
		},
		{
			name: "non-primary",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: New COMPONENT: primary = no, bootstrap = no, my_idx = 0, memb_num = 2",
			expected: regexTestState{
				Ctx:   types.LogCtx{MemberCount: 2},
				State: "NON-PRIMARY",
			},
			expectedOut: "NON-PRIMARY(n=2)",
			key:         "RegexNewComponent",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 84580 [Note] [MY-000000] [Galera] evs::proto(9a826787-9e98, LEAVING, view_id(REG,4971d113-87b0,22)) suspecting node: 4971d113-87b0",
			input: regexTestState{
				HashToIP: map[string]string{},
			},
			expected: regexTestState{
				HashToIP: map[string]string{},
			},
			expectedOut: "4971d113-87b0 suspected to be down",
			key:         "RegexNodeSuspect",
		},
		{
			name: "with known ip",
			log:  "2001-01-01T01:01:01.000000Z 84580 [Note] [MY-000000] [Galera] evs::proto(9a826787-9e98, LEAVING, view_id(REG,4971d113-87b0,22)) suspecting node: 4971d113-87b0",
			input: regexTestState{
				HashToIP: map[string]string{"4971d113-87b0": "172.17.0.2"},
			},
			expected: regexTestState{
				HashToIP: map[string]string{"4971d113-87b0": "172.17.0.2"},
			},
			expectedOut: "172.17.0.2 suspected to be down",
			key:         "RegexNodeSuspect",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: remote endpoint tcp://172.17.0.2:4567 changed identity 84953af9 -> 5a478da2",
			input: regexTestState{
				HashToIP: map[string]string{"84953af9": "172.17.0.2"},
			},
			expected: regexTestState{
				HashToIP: map[string]string{"84953af9": "172.17.0.2", "5a478da2": "172.17.0.2"},
			},
			expectedOut: "172.17.0.2 changed identity",
			key:         "RegexNodeChangedIdentity",
		},
		{
			name: "with complete uuid",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] remote endpoint ssl://172.17.0.2:4567 changed identity 595812bc-9c79-11ec-ad3f-3a7953bcc2fc -> 595812bc-9c79-11ec-ad40-3a7953bcc2fc",
			input: regexTestState{
				HashToIP: map[string]string{"595812bc-ad3f": "172.17.0.2"},
			},
			expected: regexTestState{
				HashToIP: map[string]string{"595812bc-ad3f": "172.17.0.2", "595812bc-ad40": "172.17.0.2"},
			},
			expectedOut: "172.17.0.2 changed identity",
			key:         "RegexNodeChangedIdentity",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [Galera] It may not be safe to bootstrap the cluster from this node. It was not the last one to leave the cluster and may not contain all the updates. To force cluster bootstrap with this node, edit the grastate.dat file manually and set safe_to_bootstrap to 1 .",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "not safe to bootstrap",
			key:         "RegexWsrepUnsafeBootstrap",
		},

		{
			log: "2001-01-01T01:01:01.481967+09:00 4 [ERROR] WSREP: Node consistency compromised, aborting...",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "consistency compromised",
			key:         "RegexWsrepConsistenctyCompromised",
		},
		{
			log: "2001-01-01T01:01:01.000000Z 86 [ERROR] WSREP: Node consistency compromized, aborting...",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "consistency compromised",
			key:         "RegexWsrepConsistenctyCompromised",
		},

		{
			log:         "2001-01-01  5:06:12 47285568576576 [Note] WSREP: gcomm: bootstrapping new group 'cluster'",
			expectedOut: "bootstrapping",
			key:         "RegexBootstrap",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Found saved state: 8e862473-455e-11e8-a0ca-3fcd8faf3209:-1, safe_to_bootstrap: 1",
			expectedOut: "safe_to_bootstrap: 1",
			key:         "RegexSafeToBootstrapSet",
		},
		{
			name:        "should not match",
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Found saved state: 8e862473-455e-11e8-a0ca-3fcd8faf3209:-1, safe_to_bootstrap: 0",
			expectedErr: true,
			key:         "RegexSafeToBootstrapSet",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Warning] [MY-000000] [Galera] Could not open state file for reading: '/var/lib/mysql//grastate.dat'",
			expectedOut: "no grastate.dat file",
			key:         "RegexNoGrastate",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Warning] [MY-000000] [Galera] No persistent state found. Bootstraping with default state",
			expectedOut: "bootstrapping(empty grastate)",
			key:         "RegexBootstrappingDefaultState",
		},
	}

	iterateRegexTest(t, ViewsMap, tests)
}
