package regex

import (
	"testing"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
)

func TestIdentsRegex(t *testing.T) {
	tests := []regexTest{
		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] (90002222-1111, 'ssl://0.0.0.0:4567') Found matching local endpoint for a connection, blacklisting address ssl://127.0.0.1:4567",
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnIPs: []string{"127.0.0.1"}},
			},
			expectedOut: "127.0.0.1 is local",
			key:         "RegexSourceNode",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Passing config to GCS: base_dir = /var/lib/mysql/; base_host = 127.0.0.1; base_port = 4567; cert.log_conflicts = no; cert.optimistic_pa = no; debug = no; evs.auto_evict = 0; evs.delay_margin = PT1S; evs.delayed_keep_period = PT30S; evs.inactive_check_period = PT0.5S; evs.inactive_timeout = PT15S; evs.join_retrans_period = PT1S; evs.max_install_timeouts = 3; evs.send_window = 10; evs.stats_report_period = PT1M; evs.suspect_timeout = PT5S; evs.user_send_window = 4; evs.view_forget_timeout = PT24H; gcache.dir = /data/mysql/; gcache.freeze_purge_at_seqno = -1; gcache.keep_pages_count = 0; gcache.keep_pages_size = 0; gcache.mem_size = 0; gcache.name = galera.cache; gcache.page_size = 128M; gcache.recover = yes; gcache.size = 128M; gcomm.thread_prio = ; gcs.fc_debug = 0; gcs.fc_factor = 1.0; gcs.fc_limit = 100; gcs.fc_master_slave = no; gcs.max_packet_size = 64500; gcs.max_throttle = 0.25; gcs.recv_q_hard_limit = 9223372036854775807; gcs.recv_q_soft_limit = 0.25; gcs.sync_donor = no; gmcast.segment = 0; gmcast.version = 0; pc.announce_timeout = PT3S; pc.checksum = false; pc.ignore_quorum = false; pc.ignore_sb = false; pc.npvo = false; pc.recovery = true; pc.version = 0; pc.wait_prim = true; pc.wait_prim_timeout = PT30S; pc.weight = 1; protonet.backend = asio; protonet.version = 0; repl.causal_read_timeout = PT30S; repl.commit_order = 3; repl.key_format = FLAT8; repl.max_ws_size = 2147483647; repl.proto_max = 10; socket.checksum = 2; socket.recv_buf_size = auto; socket.send_buf_size = auto; socket.ssl_ca = ca.pem; socket.ssl_cert = server-cert.pem; socket.ssl_cipher = ; socket.ssl_compression = YES; socket.ssl_key = server-key.pem;",
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnIPs: []string{"127.0.0.1"}},
			},
			expectedOut: "127.0.0.1 is local",
			key:         "RegexBaseHost",
		},

		{
			log: "        0: 015702fc-32f5-11ed-a4ca-267f97316394, node1",
			input: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "0",
					MemberCount: 1,
					OwnHashes:   []string{},
					OwnNames:    []string{},
				},
				HashToNodeNames: map[string]string{},
				State:           "PRIMARY",
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "0",
					MemberCount: 1,
					OwnHashes:   []string{"015702fc-a4ca"},
					OwnNames:    []string{"node1"},
				},
				HashToNodeNames: map[string]string{"015702fc-a4ca": "node1"},
				State:           "PRIMARY",
			},
			expectedOut: "015702fc-a4ca is node1",
			key:         "RegexMemberAssociations",
		},
		{
			log: "        0: 015702fc-32f5-11ed-a4ca-267f97316394, node1",
			input: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "0",
					MemberCount: 1,
					OwnHashes:   []string{},
					OwnNames:    []string{},
				},
				HashToNodeNames: map[string]string{},
				State:           "NON-PRIMARY",
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "0",
					MemberCount: 1,
					OwnHashes:   []string{"015702fc-a4ca"},
					OwnNames:    []string{"node1"},
				},
				HashToNodeNames: map[string]string{"015702fc-a4ca": "node1"},
				State:           "NON-PRIMARY",
			},
			expectedOut: "015702fc-a4ca is node1",
			key:         "RegexMemberAssociations",
		},
		{
			log: "        0: 015702fc-32f5-11ed-a4ca-267f97316394, node1",
			input: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "0",
					MemberCount: 2,
				},
				HashToNodeNames: map[string]string{},
				State:           "NON-PRIMARY",
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "0",
					MemberCount: 2,
				},
				HashToNodeNames: map[string]string{"015702fc-a4ca": "node1"},
				State:           "NON-PRIMARY",
			},
			expectedOut: "015702fc-a4ca is node1",
			key:         "RegexMemberAssociations",
		},
		{
			log: "        1: 015702fc-32f5-11ed-a4ca-267f97316394, node1",
			input: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "1",
					MemberCount: 1,
					OwnHashes:   []string{},
					OwnNames:    []string{},
				},
				HashToNodeNames: map[string]string{},
				State:           "PRIMARY",
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "1",
					MemberCount: 1,
					OwnHashes:   []string{"015702fc-a4ca"},
					OwnNames:    []string{"node1"},
				},
				HashToNodeNames: map[string]string{"015702fc-a4ca": "node1"},
				State:           "PRIMARY",
			},
			expectedOut: "015702fc-a4ca is node1",
			key:         "RegexMemberAssociations",
		},
		{
			log: "        0: 015702fc-32f5-11ed-a4ca-267f97316394, node1",
			input: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "1",
					MemberCount: 1,
				},
				HashToNodeNames: map[string]string{},
				State:           "PRIMARY",
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "1",
					MemberCount: 1,
				},
				HashToNodeNames: map[string]string{"015702fc-a4ca": "node1"},
				State:           "PRIMARY",
			},
			expectedOut: "015702fc-a4ca is node1",
			key:         "RegexMemberAssociations",
		},
		{
			log: "        0: 015702fc-32f5-11ed-a4ca-267f97316394, node1.with.complete.fqdn",
			input: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "1",
					MemberCount: 1,
				},
				HashToNodeNames: map[string]string{},
				State:           "PRIMARY",
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "1",
					MemberCount: 1,
				},
				HashToNodeNames: map[string]string{"015702fc-a4ca": "node1"},
				State:           "PRIMARY",
			},
			expectedOut: "015702fc-a4ca is node1",
			key:         "RegexMemberAssociations",
		},
		{
			name: "name too long and truncated",
			log:  "        0: 015702fc-32f5-11ed-a4ca-267f97316394, name_so_long_it_will_get_trunca",
			input: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "1",
					MemberCount: 1,
				},
				State: "PRIMARY",
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx:       "1",
					MemberCount: 1,
				},
				State: "PRIMARY",
			},
			expectedOut:          "",
			displayerExpectedNil: true,
			key:                  "RegexMemberAssociations",
		},

		{
			log:         "  members(1):",
			expectedOut: "view member count: 1",
			expected: regexTestState{
				LogCtx: types.LogCtx{MemberCount: 1},
			},
			key: "RegexMemberCount",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 1 [Note] [MY-000000] [Galera] ####### My UUID: 60205de0-5cf6-11ec-8884-3a01908be11a",
			input: regexTestState{
				LogCtx: types.LogCtx{},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					OwnHashes: []string{"60205de0-8884"},
				},
			},
			expectedOut: "60205de0-8884 is local",
			key:         "RegexOwnUUID",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: (9509c194, 'tcp://0.0.0.0:4567') turning message relay requesting on, nonlive peers:",
			input: regexTestState{
				LogCtx: types.LogCtx{},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					OwnHashes: []string{"9509c194"},
				},
			},
			expectedOut: "9509c194 is local",
			key:         "RegexOwnUUIDFromMessageRelay",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: New COMPONENT: primary = yes, bootstrap = no, my_idx = 0, memb_num = 2",
			input: regexTestState{
				LogCtx: types.LogCtx{},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx: "0",
				},
			},
			expectedOut: "my_idx=0",
			key:         "RegexMyIDXFromComponent",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: (9509c194, 'tcp://0.0.0.0:4567') connection established to 838ebd6d tcp://172.17.0.2:4567",
			input: regexTestState{
				LogCtx: types.LogCtx{},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					OwnHashes: []string{"9509c194"},
				},
			},
			expectedOut: "9509c194 is local",
			key:         "RegexOwnUUIDFromEstablished",
		},

		{
			log: "  own_index: 1",
			input: regexTestState{
				LogCtx: types.LogCtx{},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{
					MyIdx: "1",
				},
			},
			expectedOut: "my_idx=1",
			key:         "RegexOwnIndexFromView",
		},
	}

	iterateRegexTest(t, IdentsMap, tests)
}
