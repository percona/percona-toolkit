package regex

import (
	"testing"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
)

func TestSSTRegex(t *testing.T) {
	tests := []regexTest{
		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Member 2.0 (node2) requested state transfer from '*any*'. Selected 0.0 (node1)(SYNCED) as donor.",
			input: regexTestState{
				Ctx: types.LogCtx{SSTs: map[string]types.SST{}},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{SSTs: map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", SelectionTimestamp: timeMustParse("2001-01-01T01:01:01.000000Z")}}},
			},
			expectedOut: "node1 will resync node2",
			key:         "RegexSSTRequestSuccess",
		},
		{
			name: "with fqdn",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 2.0 (node2.host.com) requested state transfer from '*any*'. Selected 0.0 (node1.host.com)(SYNCED) as donor.",
			input: regexTestState{
				Ctx: types.LogCtx{SSTs: map[string]types.SST{}},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{SSTs: map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", SelectionTimestamp: timeMustParse("2001-01-01T01:01:01.000000Z")}}},
			},
			expectedOut: "node1 will resync node2",
			key:         "RegexSSTRequestSuccess",
		},
		{
			name: "joining",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Member 2.0 (node2) requested state transfer from '*any*'. Selected 0.0 (node1)(SYNCED) as donor.",
			input: regexTestState{
				Ctx: types.LogCtx{
					OwnNames: []string{"node2"},
					SSTs:     map[string]types.SST{},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					OwnNames: []string{"node2"},
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", SelectionTimestamp: timeMustParse("2001-01-01T01:01:01.000000Z")}},
				},
			},
			expectedOut: "node1 will resync local node",
			key:         "RegexSSTRequestSuccess",
		},
		{
			name: "donor",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Member 2.0 (node2) requested state transfer from '*any*'. Selected 0.0 (node1)(SYNCED) as donor.",
			input: regexTestState{
				Ctx: types.LogCtx{
					OwnNames: []string{"node1"},
					SSTs:     map[string]types.SST{},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					OwnNames: []string{"node1"},
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", SelectionTimestamp: timeMustParse("2001-01-01T01:01:01.000000Z")}},
				},
			},
			expectedOut: "local node will resync node2",
			key:         "RegexSSTRequestSuccess",
		},

		{
			log: "2001-01-01 01:01:01.164  WARN: Member 1.0 (node2) requested state transfer from 'node1', but it is impossible to select State Transfer donor: Resource temporarily unavailable",
			input: regexTestState{
				Ctx: types.LogCtx{},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{},
			},
			expectedOut: "node2 cannot find donor",
			key:         "RegexSSTResourceUnavailable",
		},
		{
			name: "local",
			log:  "2001-01-01 01:01:01.164  WARN: Member 1.0 (node2) requested state transfer from 'node1', but it is impossible to select State Transfer donor: Resource temporarily unavailable",
			input: regexTestState{
				Ctx: types.LogCtx{
					OwnNames: []string{"node2"},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					OwnNames: []string{"node2"},
				},
			},
			expectedOut: "cannot find donor",
			key:         "RegexSSTResourceUnavailable",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to 2.0 (node2) complete.",
			input: regexTestState{
				Ctx: types.LogCtx{
					SSTs: map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs: map[string]types.SST{},
				},
			},
			expectedOut: "node1 synced node2",
			key:         "RegexSSTComplete",
		},
		{
			name: "joiner",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to 2.0 (node2) complete.",
			input: regexTestState{
				Ctx: types.LogCtx{
					OwnNames: []string{"node2"},
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{},
					OwnNames: []string{"node2"},
				},
			},
			expectedOut: "got SST from node1",
			key:         "RegexSSTComplete",
		},
		{
			name: "joiner ist",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to 2.0 (node2) complete.",
			input: regexTestState{
				Ctx: types.LogCtx{
					OwnNames: []string{"node2"},
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{},
					OwnNames: []string{"node2"},
				},
			},
			expectedOut: "got IST from node1",
			key:         "RegexSSTComplete",
		},
		{
			name: "donor",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to 2.0 (node2) complete.",
			input: regexTestState{
				Ctx: types.LogCtx{
					OwnNames: []string{"node1"},
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{},
					OwnNames: []string{"node1"},
				},
			},
			expectedOut: "finished sending SST to node2",
			key:         "RegexSSTComplete",
		},
		{
			name: "donor ist",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to 2.0 (node2) complete.",
			input: regexTestState{
				Ctx: types.LogCtx{
					OwnNames: []string{"node1"},
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{},
					OwnNames: []string{"node1"},
				},
			},
			expectedOut: "finished sending IST to node2",
			key:         "RegexSSTComplete",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to -1.-1 (left the group) complete.",
			input: regexTestState{
				Ctx: types.LogCtx{},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{},
			},
			expectedOut: "node1 synced ??(node left)",
			key:         "RegexSSTCompleteUnknown",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [WSREP] Process completed with error: wsrep_sst_xtrabackup-v2 --role 'donor' --address '172.17.0.2:4444/xtrabackup_sst//1' --socket '/var/lib/mysql/mysql.sock' --datadir '/var/lib/mysql/' --basedir '/usr/' --plugindir '/usr/lib64/mysql/plugin/' --defaults-file '/etc/my.cnf' --defaults-group-suffix '' --mysqld-version '8.0.28-19.1'   '' --gtid '9db0bcdf-b31a-11ed-a398-2a4cfdd82049:1' : 22 (Invalid argument)",
			expectedOut: "SST error",
			key:         "RegexSSTError",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 1328586 [Note] [MY-000000] [WSREP] Initiating SST cancellation",
			expectedOut: "former SST cancelled",
			key:         "RegexSSTCancellation",
		},

		{
			log: "2001-01-01T01:01:01.000000Z WSREP_SST: [INFO] Proceeding with SST.........",
			input: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
					OwnNames: []string{"node2"},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "SST"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expectedOut: "receiving SST",
			key:         "RegexSSTProceeding",
		},

		{
			log: "2001-01-01T01:01:01.000000Z WSREP_SST: [INFO] Streaming the backup to joiner at 172.17.0.2 4444",
			expected: regexTestState{
				State: "DONOR",
			},
			expectedOut: "SST to 172.17.0.2",
			key:         "RegexSSTStreamingTo",
		},

		{
			log:         "2001-01-01 01:01:01 140446376740608 [Note] WSREP: IST received: e00c4fff-c4b0-11e9-96a8-0f9789de42ad:69472531",
			expectedOut: "IST received(seqno:69472531)",
			key:         "RegexISTReceived",
		},

		{
			log: "2001-01-01  1:01:01 140433613571840 [Note] WSREP: async IST sender starting to serve tcp://172.17.0.2:4568 sending 2-116",
			input: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
					OwnNames: []string{"node1"},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
					OwnNames: []string{"node1"},
				},
				State: "DONOR",
			},
			expectedOut: "IST to 172.17.0.2(seqno:116)",
			key:         "RegexISTSender",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Prepared IST receiver for 114-116, listening at: ssl://172.17.0.2:4568",
			input: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
					OwnNames: []string{"node2"},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expectedOut: "will receive IST(seqno:116)",
			key:         "RegexISTReceiver",
		},
		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Prepared IST receiver for 0-116, listening at: ssl://172.17.0.2:4568",
			input: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
					OwnNames: []string{"node2"},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "SST"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expectedOut: "will receive SST",
			key:         "RegexISTReceiver",
		},
		{
			name: "mdb variant",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Prepared IST receiver, listening at: ssl://172.17.0.2:4568",
			input: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
					OwnNames: []string{"node2"},
				},
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expectedOut: "will receive IST",
			key:         "RegexISTReceiver",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Warning] [MY-000000] [Galera] 0.1 (node): State transfer to -1.-1 (left the group) failed: -111 (Connection refused)",
			expectedOut: "node failed to sync ??(node left)",
			key:         "RegexSSTFailedUnknown",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Warning] [MY-000000] [Galera] 0.1 (node): State transfer to 0.2 (node2) failed: -111 (Connection refused)",
			expectedOut: "node failed to sync node2",
			key:         "RegexSSTStateTransferFailed",
		},
		{
			log:                  "2001-01-01T01:01:01.000000Z 0 [Warning] [MY-000000] [Galera] 0.1 (node): State transfer to -1.-1 (left the group) failed: -111 (Connection refused)",
			displayerExpectedNil: true,
			key:                  "RegexSSTStateTransferFailed",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 1 [Note] WSREP: Failed to prepare for incremental state transfer: Local state UUID (00000000-0000-0000-0000-000000000000) does not match group state UUID (ed16c932-84b3-11ed-998c-8e3ae5bc328f): 1 (Operation not permitted)",
			input: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "SST"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expectedOut: "IST is not applicable",
			key:         "RegexFailedToPrepareIST",
		},
		{
			log: "2001-01-01T01:01:01.000000Z 1 [Warning] WSREP: Failed to prepare for incremental state transfer: Local state seqno is undefined: 1 (Operation not permitted)",
			input: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "SST"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expectedOut: "IST is not applicable",
			key:         "RegexFailedToPrepareIST",
		},

		{
			log: "2001-01-01T01:01:01.000000Z WSREP_SST: [INFO] Bypassing SST. Can work it through IST",
			input: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expectedOut: "IST will be used",
			key:         "RegexBypassSST",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [WSREP-SST] xtrabackup_ist received from donor: Running IST",
			input: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expected: regexTestState{
				Ctx: types.LogCtx{
					SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
					OwnNames: []string{"node2"},
				},
				State: "JOINER",
			},
			expectedOut: "IST running",
			key:         "RegexXtrabackupISTReceived",
		},

		{
			log:         "2001/01/01 01:01:01 socat[23579] E connect(62, AF=2 172.17.0.20:4444, 16): Connection refused",
			expectedOut: "socat: connection refused",
			key:         "RegexSocatConnRefused",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [WSREP-SST] Preparing the backup at /var/lib/mysql/sst-xb-tmpdir",
			expectedOut: "preparing SST backup",
			key:         "RegexPreparingBackup",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z WSREP_SST: [ERROR] Possible timeout in receving first data from donor in gtid/keyring stage",
			expectedOut: "timeout from donor in gtid/keyring stage",
			key:         "RegexTimeoutReceivingFirstData",
		},

		{
			log:         "2001-01-01 01:01:01 140666176771840 [ERROR] WSREP: gcs/src/gcs_group.cpp:gcs_group_handle_join_msg():736: Will never receive state. Need to abort.",
			expectedOut: "will never receive SST, aborting",
			key:         "RegexWillNeverReceive",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [WSREP-SST] Preparing the backup at /var/lib/mysql/sst-xb-tmpdir",
			expectedOut: "preparing SST backup",
			key:         "RegexPreparingBackup",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z WSREP_SST: [ERROR] Possible timeout in receving first data from donor in gtid/keyring stage",
			expectedOut: "timeout from donor in gtid/keyring stage",
			key:         "RegexTimeoutReceivingFirstData",
		},

		{
			log:         "2001-01-01 01:01:01 140666176771840 [ERROR] WSREP: gcs/src/gcs_group.cpp:gcs_group_handle_join_msg():736: Will never receive state. Need to abort.",
			expectedOut: "will never receive SST, aborting",
			key:         "RegexWillNeverReceive",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [ERROR] WSREP: async IST sender failed to serve tcp://172.17.0.2:4568: ist send failed: asio.system:32', asio error 'write: Broken pipe': 32 (Broken pipe)",
			expectedOut: "IST to 172.17.0.2 failed: Broken pipe",
			key:         "RegexISTFailed",
		},
		{
			log:         "2001-01-01 01:10:01 28949 [ERROR] WSREP: async IST sender failed to serve tcp://172.17.0.2:4568: ist send failed: asio.system:104', asio error 'write: Connection reset by peer': 104 (Connection reset by peer)",
			expectedOut: "IST to 172.17.0.2 failed: Connection reset by peer",
			key:         "RegexISTFailed",
		},
		{
			log:         "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [Galera] async IST sender failed to serve ssl://172.17.0.2:4568: ist send failed: ', asio error 'Got unexpected return from write: eof: 71 (Protocol error)",
			expectedOut: "IST to 172.17.0.2 failed: Protocol error",
			key:         "RegexISTFailed",
		},
		{
			log: `{\"log\":\"2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [Galera] async IST sender failed to serve ssl://172.17.0.2:4568: ist send failed: ', asio error 'Got unexpected return from write: eof: 71 (Protocol error)\n\t at galerautils/src/gu_asio_stream_react.cpp:write():195': 71 (Protocol error)\n\t at galera/src/ist.cpp:send():856\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"
`,
			expectedOut: "IST to 172.17.0.2 failed: Protocol error",
			key:         "RegexISTFailed",
		},
	}

	iterateRegexTest(t, SSTMap, tests)
}
