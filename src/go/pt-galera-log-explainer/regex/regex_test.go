package regex

import (
	"io/ioutil"
	"os/exec"
	"testing"
	"time"

	"github.com/davecgh/go-spew/spew"
	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"github.com/pkg/errors"
)

func TestRegexes(t *testing.T) {
	utils.SkipColor = true
	tests := []struct {
		name                 string
		log, expectedOut     string
		inputCtx             types.LogCtx
		inputState           string
		expectedState        string
		expectedCtx          types.LogCtx
		displayerExpectedNil bool
		expectedErr          bool
		mapToTest            types.RegexMap
		key                  string
	}{
		{
			name:          "8.0.30-22",
			log:           "2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 8.0.30-22) starting as process 1",
			expectedCtx:   types.LogCtx{Version: "8.0.30"},
			expectedState: "OPEN",
			expectedOut:   "starting(8.0.30)",
			mapToTest:     EventsMap,
			key:           "RegexStarting",
		},
		{
			name:          "8.0.2-22",
			log:           "2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 8.0.2-22) starting as process 1",
			expectedCtx:   types.LogCtx{Version: "8.0.2"},
			expectedState: "OPEN",
			expectedOut:   "starting(8.0.2)",
			mapToTest:     EventsMap,
			key:           "RegexStarting",
		},
		{
			name:          "5.7.31-34-log",
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] /usr/sbin/mysqld (mysqld 5.7.31-34-log) starting as process 2 ...",
			expectedCtx:   types.LogCtx{Version: "5.7.31"},
			expectedState: "OPEN",
			expectedOut:   "starting(5.7.31)",
			mapToTest:     EventsMap,
			key:           "RegexStarting",
		},
		{
			name:          "10.4.25-MariaDB-log",
			log:           "2001-01-01  01:01:01 0 [Note] /usr/sbin/mysqld (mysqld 10.4.25-MariaDB-log) starting as process 2 ...",
			expectedCtx:   types.LogCtx{Version: "10.4.25"},
			expectedState: "OPEN",
			expectedOut:   "starting(10.4.25)",
			mapToTest:     EventsMap,
			key:           "RegexStarting",
		},
		{
			name:          "10.2.31-MariaDB-1:10.2.31+maria~bionic-log",
			log:           "2001-01-01  01:01:01 0 [Note] /usr/sbin/mysqld (mysqld 10.2.31-MariaDB-1:10.2.31+maria~bionic-log) starting as process 2 ...",
			expectedCtx:   types.LogCtx{Version: "10.2.31"},
			expectedState: "OPEN",
			expectedOut:   "starting(10.2.31)",
			mapToTest:     EventsMap,
			key:           "RegexStarting",
		},
		{
			name:          "5.7.28-enterprise-commercial-advanced-log",
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] /usr/sbin/mysqld (mysqld 5.7.28-enterprise-commercial-advanced-log) starting as process 2 ...",
			expectedCtx:   types.LogCtx{Version: "5.7.28"},
			expectedState: "OPEN",
			expectedOut:   "starting(5.7.28)",
			mapToTest:     EventsMap,
			key:           "RegexStarting",
		},
		{
			name:          "8.0.30 operator",
			log:           "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 8.0.30-22.1) starting as process 1\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			expectedCtx:   types.LogCtx{Version: "8.0.30"},
			expectedState: "OPEN",
			expectedOut:   "starting(8.0.30)",
			mapToTest:     EventsMap,
			key:           "RegexStarting",
		},
		{
			name:                 "wrong version 7.0.0",
			log:                  "2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 7.0.0-22) starting as process 1",
			displayerExpectedNil: true,
			mapToTest:            EventsMap,
			key:                  "RegexStarting",
		},
		{
			name:                 "wrong version 8.12.0",
			log:                  "2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 8.12.0-22) starting as process 1",
			displayerExpectedNil: true,
			mapToTest:            EventsMap,
			key:                  "RegexStarting",
		},
		{
			name:          "could not catch how it stopped",
			log:           "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 8.0.30-22.1) starting as process 1\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			expectedCtx:   types.LogCtx{Version: "8.0.30"},
			expectedState: "OPEN",
			inputState:    "OPEN",
			expectedOut:   "starting(8.0.30, could not catch how/when it stopped)",
			mapToTest:     EventsMap,
			key:           "RegexStarting",
		},

		{

			log:           "2001-01-01T01:01:01.000000Z 0 [System] [MY-010910] [Server] /usr/sbin/mysqld: Shutdown complete (mysqld 8.0.23-14.1)  Percona XtraDB Cluster (GPL), Release rel14, Revision d3b9a1d, WSREP version 26.4.3.",
			expectedState: "CLOSED",
			expectedOut:   "shutdown complete",
			mapToTest:     EventsMap,
			key:           "RegexShutdownComplete",
		},

		{
			log:           "2001-01-01 01:01:01 140430087788288 [Note] WSREP: /opt/rh-mariadb102/root/usr/libexec/mysqld: Terminated.",
			expectedState: "CLOSED",
			expectedOut:   "terminated",
			mapToTest:     EventsMap,
			key:           "RegexTerminated",
		},
		{
			log:           "2001-01-01T01:01:01.000000Z 8 [Note] WSREP: /usr/sbin/mysqld: Terminated.",
			expectedState: "CLOSED",
			expectedOut:   "terminated",
			mapToTest:     EventsMap,
			key:           "RegexTerminated",
		},

		{
			log:           "01:01:01 UTC - mysqld got signal 6 ;",
			expectedState: "CLOSED",
			expectedOut:   "crash: got signal 6",
			mapToTest:     EventsMap,
			key:           "RegexGotSignal6",
		},
		{
			log:           "01:01:01 UTC - mysqld got signal 11 ;",
			expectedState: "CLOSED",
			expectedOut:   "crash: got signal 11",
			mapToTest:     EventsMap,
			key:           "RegexGotSignal11",
		},

		{
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [WSREP] Received shutdown signal. Will sleep for 10 secs before initiating shutdown. pxc_maint_mode switched to SHUTDOWN",
			expectedState: "CLOSED",
			expectedOut:   "received shutdown",
			mapToTest:     EventsMap,
			key:           "RegexShutdownSignal",
		},
		{
			log:           "2001-01-01 01:01:01 139688443508480 [Note] /opt/rh-mariadb102/root/usr/libexec/mysqld (unknown): Normal shutdown",
			expectedState: "CLOSED",
			expectedOut:   "received shutdown",
			mapToTest:     EventsMap,
			key:           "RegexShutdownSignal",
		},
		{
			log:           "2001-01-01  1:01:01 0 [Note] /usr/sbin/mariadbd (initiated by: unknown): Normal shutdown",
			expectedState: "CLOSED",
			expectedOut:   "received shutdown",
			mapToTest:     EventsMap,
			key:           "RegexShutdownSignal",
		},

		{
			log:           "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-010119] [Server] Aborting",
			expectedState: "CLOSED",
			expectedOut:   "ABORTING",
			mapToTest:     EventsMap,
			key:           "RegexAborting",
		},

		{
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] wsrep_load(): loading provider library '/usr/lib64/galera4/libgalera_smm.so'",
			expectedState: "OPEN",
			expectedOut:   "started(cluster)",
			mapToTest:     EventsMap,
			key:           "RegexWsrepLoad",
		},
		{
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] wsrep_load(): loading provider library 'none'",
			expectedState: "OPEN",
			expectedOut:   "started(standalone)",
			mapToTest:     EventsMap,
			key:           "RegexWsrepLoad",
		},

		{
			log:           "2001-01-01 01:01:01 140557650536640 [Note] WSREP: wsrep_load(): loading provider library '/opt/rh-mariadb102/root/usr/lib64/galera/libgalera_smm.so'",
			expectedState: "OPEN",
			expectedOut:   "started(cluster)",
			mapToTest:     EventsMap,
			key:           "RegexWsrepLoad",
		},

		{
			log:           "2001-01-01T01:01:01.000000Z 3 [Note] [MY-000000] [Galera] Recovered position from storage: 7780bb61-87cf-11eb-b53b-6a7c64b0fee3:23506640",
			expectedState: "RECOVERY",
			expectedOut:   "wsrep recovery",
			mapToTest:     EventsMap,
			key:           "RegexWsrepRecovery",
		},
		{
			log:           " INFO: WSREP: Recovered position 9a4db4a5-5cf1-11ec-940d-6ba8c5905c02:30",
			expectedState: "RECOVERY",
			expectedOut:   "wsrep recovery",
			mapToTest:     EventsMap,
			key:           "RegexWsrepRecovery",
		},
		{
			log:           " INFO: WSREP: Recovered position 00000000-0000-0000-0000-000000000000:-1",
			expectedState: "RECOVERY",
			expectedOut:   "wsrep recovery",
			mapToTest:     EventsMap,
			key:           "RegexWsrepRecovery",
		},
		{
			name:          "not unknown",
			log:           " INFO: WSREP: Recovered position 00000000-0000-0000-0000-000000000000:-1",
			expectedState: "RECOVERY",
			inputState:    "OPEN",
			expectedOut:   "wsrep recovery",
			mapToTest:     EventsMap,
			key:           "RegexWsrepRecovery",
		},
		{
			name:          "could not catch how it stopped",
			log:           " INFO: WSREP: Recovered position 00000000-0000-0000-0000-000000000000:-1",
			expectedState: "RECOVERY",
			inputState:    "SYNCED",
			expectedOut:   "wsrep recovery(could not catch how/when it stopped)",
			mapToTest:     EventsMap,
			key:           "RegexWsrepRecovery",
		},

		{
			log:         "2001-01-01T01:01:01.045425-05:00 0 [ERROR] unknown variable 'validate_password_length=8'",
			expectedOut: "unknown variable: validate_password_le...",
			mapToTest:   EventsMap,
			key:         "RegexUnknownConf",
		},

		{
			log:           "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-013183] [InnoDB] Assertion failure: btr0cur.cc:296:btr_page_get_prev(get_block->frame, mtr) == page_get_page_no(page) thread 139538894652992",
			expectedState: "CLOSED",
			expectedOut:   "ASSERTION FAILURE",
			mapToTest:     EventsMap,
			key:           "RegexAssertionFailure",
		},

		{
			log:           "2001-01-01  5:06:12 47285568576576 [ERROR] WSREP: failed to open gcomm backend connection: 98: error while trying to listen 'tcp://0.0.0.0:4567?socket.non_blocking=1', asio error 'bind: Address already in use': 98 (Address already in use)",
			expectedState: "CLOSED",
			expectedOut:   "bind address already used",
			mapToTest:     EventsMap,
			key:           "RegexBindAddressAlreadyUsed",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [Galera] gcs/src/gcs_group.cpp:group_post_state_exchange():431: Reversing history: 150 -> 10, this member has applied 140 more events than the primary component.Data loss is possible. Must abort.",
			expectedOut: "having 140 more events than the other nodes, data loss possible",
			mapToTest:   EventsMap,
			key:         "RegexReversingHistory",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] (90002222-1111, 'ssl://0.0.0.0:4567') Found matching local endpoint for a connection, blacklisting address ssl://127.0.0.1:4567",
			expectedCtx: types.LogCtx{OwnIPs: []string{"127.0.0.1"}},
			expectedOut: "127.0.0.1 is local",
			mapToTest:   IdentsMap,
			key:         "RegexSourceNode",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Passing config to GCS: base_dir = /var/lib/mysql/; base_host = 127.0.0.1; base_port = 4567; cert.log_conflicts = no; cert.optimistic_pa = no; debug = no; evs.auto_evict = 0; evs.delay_margin = PT1S; evs.delayed_keep_period = PT30S; evs.inactive_check_period = PT0.5S; evs.inactive_timeout = PT15S; evs.join_retrans_period = PT1S; evs.max_install_timeouts = 3; evs.send_window = 10; evs.stats_report_period = PT1M; evs.suspect_timeout = PT5S; evs.user_send_window = 4; evs.view_forget_timeout = PT24H; gcache.dir = /data/mysql/; gcache.freeze_purge_at_seqno = -1; gcache.keep_pages_count = 0; gcache.keep_pages_size = 0; gcache.mem_size = 0; gcache.name = galera.cache; gcache.page_size = 128M; gcache.recover = yes; gcache.size = 128M; gcomm.thread_prio = ; gcs.fc_debug = 0; gcs.fc_factor = 1.0; gcs.fc_limit = 100; gcs.fc_master_slave = no; gcs.max_packet_size = 64500; gcs.max_throttle = 0.25; gcs.recv_q_hard_limit = 9223372036854775807; gcs.recv_q_soft_limit = 0.25; gcs.sync_donor = no; gmcast.segment = 0; gmcast.version = 0; pc.announce_timeout = PT3S; pc.checksum = false; pc.ignore_quorum = false; pc.ignore_sb = false; pc.npvo = false; pc.recovery = true; pc.version = 0; pc.wait_prim = true; pc.wait_prim_timeout = PT30S; pc.weight = 1; protonet.backend = asio; protonet.version = 0; repl.causal_read_timeout = PT30S; repl.commit_order = 3; repl.key_format = FLAT8; repl.max_ws_size = 2147483647; repl.proto_max = 10; socket.checksum = 2; socket.recv_buf_size = auto; socket.send_buf_size = auto; socket.ssl_ca = ca.pem; socket.ssl_cert = server-cert.pem; socket.ssl_cipher = ; socket.ssl_compression = YES; socket.ssl_key = server-key.pem;",
			expectedCtx: types.LogCtx{OwnIPs: []string{"127.0.0.1"}},
			expectedOut: "127.0.0.1 is local",
			mapToTest:   IdentsMap,
			key:         "RegexBaseHost",
		},

		{
			log: "        0: 015702fc-32f5-11ed-a4ca-267f97316394, node1",
			inputCtx: types.LogCtx{
				MyIdx:          "0",
				MemberCount:    1,
				OwnHashes:      []string{},
				OwnNames:       []string{},
				HashToNodeName: map[string]string{},
			},
			inputState: "PRIMARY",
			expectedCtx: types.LogCtx{
				MyIdx:          "0",
				MemberCount:    1,
				OwnHashes:      []string{"015702fc-a4ca"},
				OwnNames:       []string{"node1"},
				HashToNodeName: map[string]string{"015702fc-a4ca": "node1"},
			},
			expectedState: "PRIMARY",
			expectedOut:   "015702fc-a4ca is node1",
			mapToTest:     IdentsMap,
			key:           "RegexMemberAssociations",
		},
		{
			log: "        0: 015702fc-32f5-11ed-a4ca-267f97316394, node1",
			inputCtx: types.LogCtx{
				MyIdx:          "0",
				MemberCount:    1,
				OwnHashes:      []string{},
				OwnNames:       []string{},
				HashToNodeName: map[string]string{},
			},
			inputState: "NON-PRIMARY",
			expectedCtx: types.LogCtx{
				MyIdx:          "0",
				MemberCount:    1,
				OwnHashes:      []string{"015702fc-a4ca"},
				OwnNames:       []string{"node1"},
				HashToNodeName: map[string]string{"015702fc-a4ca": "node1"},
			},
			expectedState: "NON-PRIMARY",
			expectedOut:   "015702fc-a4ca is node1",
			mapToTest:     IdentsMap,
			key:           "RegexMemberAssociations",
		},
		{
			log: "        0: 015702fc-32f5-11ed-a4ca-267f97316394, node1",
			inputCtx: types.LogCtx{
				MyIdx:          "0",
				MemberCount:    2,
				HashToNodeName: map[string]string{},
			},
			inputState: "NON-PRIMARY",
			expectedCtx: types.LogCtx{
				MyIdx:          "0",
				MemberCount:    2,
				HashToNodeName: map[string]string{"015702fc-a4ca": "node1"},
			},
			expectedState: "NON-PRIMARY",
			expectedOut:   "015702fc-a4ca is node1",
			mapToTest:     IdentsMap,
			key:           "RegexMemberAssociations",
		},
		{
			log: "        1: 015702fc-32f5-11ed-a4ca-267f97316394, node1",
			inputCtx: types.LogCtx{
				MyIdx:          "1",
				MemberCount:    1,
				OwnHashes:      []string{},
				OwnNames:       []string{},
				HashToNodeName: map[string]string{},
			},
			inputState: "PRIMARY",
			expectedCtx: types.LogCtx{
				MyIdx:          "1",
				MemberCount:    1,
				OwnHashes:      []string{"015702fc-a4ca"},
				OwnNames:       []string{"node1"},
				HashToNodeName: map[string]string{"015702fc-a4ca": "node1"},
			},
			expectedState: "PRIMARY",
			expectedOut:   "015702fc-a4ca is node1",
			mapToTest:     IdentsMap,
			key:           "RegexMemberAssociations",
		},
		{
			log: "        0: 015702fc-32f5-11ed-a4ca-267f97316394, node1",
			inputCtx: types.LogCtx{
				MyIdx:          "1",
				MemberCount:    1,
				HashToNodeName: map[string]string{},
			},
			inputState: "PRIMARY",
			expectedCtx: types.LogCtx{
				MyIdx:          "1",
				MemberCount:    1,
				HashToNodeName: map[string]string{"015702fc-a4ca": "node1"},
			},
			expectedState: "PRIMARY",
			expectedOut:   "015702fc-a4ca is node1",
			mapToTest:     IdentsMap,
			key:           "RegexMemberAssociations",
		},
		{
			log: "        0: 015702fc-32f5-11ed-a4ca-267f97316394, node1.with.complete.fqdn",
			inputCtx: types.LogCtx{
				MyIdx:          "1",
				MemberCount:    1,
				HashToNodeName: map[string]string{},
			},
			inputState: "PRIMARY",
			expectedCtx: types.LogCtx{
				MyIdx:          "1",
				MemberCount:    1,
				HashToNodeName: map[string]string{"015702fc-a4ca": "node1"},
			},
			expectedState: "PRIMARY",
			expectedOut:   "015702fc-a4ca is node1",
			mapToTest:     IdentsMap,
			key:           "RegexMemberAssociations",
		},
		{
			name: "name too long and truncated",
			log:  "        0: 015702fc-32f5-11ed-a4ca-267f97316394, name_so_long_it_will_get_trunca",
			inputCtx: types.LogCtx{
				MyIdx:       "1",
				MemberCount: 1,
			},
			inputState: "PRIMARY",
			expectedCtx: types.LogCtx{
				MyIdx:       "1",
				MemberCount: 1,
			},
			expectedState:        "PRIMARY",
			expectedOut:          "",
			displayerExpectedNil: true,
			mapToTest:            IdentsMap,
			key:                  "RegexMemberAssociations",
		},

		{
			log:         "  members(1):",
			expectedOut: "view member count: 1",
			expectedCtx: types.LogCtx{MemberCount: 1},
			mapToTest:   IdentsMap,
			key:         "RegexMemberCount",
		},

		{
			log:      "2001-01-01T01:01:01.000000Z 1 [Note] [MY-000000] [Galera] ####### My UUID: 60205de0-5cf6-11ec-8884-3a01908be11a",
			inputCtx: types.LogCtx{},
			expectedCtx: types.LogCtx{
				OwnHashes: []string{"60205de0-8884"},
			},
			expectedOut: "60205de0-8884 is local",
			mapToTest:   IdentsMap,
			key:         "RegexOwnUUID",
		},

		{
			log:      "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: (9509c194, 'tcp://0.0.0.0:4567') turning message relay requesting on, nonlive peers:",
			inputCtx: types.LogCtx{},
			expectedCtx: types.LogCtx{
				OwnHashes: []string{"9509c194"},
			},
			expectedOut: "9509c194 is local",
			mapToTest:   IdentsMap,
			key:         "RegexOwnUUIDFromMessageRelay",
		},

		{
			log:      "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: New COMPONENT: primary = yes, bootstrap = no, my_idx = 0, memb_num = 2",
			inputCtx: types.LogCtx{},
			expectedCtx: types.LogCtx{
				MyIdx: "0",
			},
			expectedOut: "my_idx=0",
			mapToTest:   IdentsMap,
			key:         "RegexMyIDXFromComponent",
		},

		{
			log:      "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: (9509c194, 'tcp://0.0.0.0:4567') connection established to 838ebd6d tcp://172.17.0.2:4567",
			inputCtx: types.LogCtx{},
			expectedCtx: types.LogCtx{
				OwnHashes: []string{"9509c194"},
			},
			expectedOut: "9509c194 is local",
			mapToTest:   IdentsMap,
			key:         "RegexOwnUUIDFromEstablished",
		},

		{
			log:      "  own_index: 1",
			inputCtx: types.LogCtx{},
			expectedCtx: types.LogCtx{
				MyIdx: "1",
			},
			expectedOut: "my_idx=1",
			mapToTest:   IdentsMap,
			key:         "RegexOwnIndexFromView",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] (60205de0-8884, 'ssl://0.0.0.0:4567') connection established to 5873acd0-baa8 ssl://172.17.0.2:4567",
			inputCtx: types.LogCtx{
				HashToIP: map[string]string{},
			},
			expectedCtx: types.LogCtx{
				HashToIP: map[string]string{"5873acd0-baa8": "172.17.0.2"},
			},
			expectedOut: "172.17.0.2 established",
			mapToTest:   ViewsMap,
			key:         "RegexNodeEstablished",
		},
		{
			name: "established to node's own ip",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] (60205de0-8884, 'ssl://0.0.0.0:4567') connection established to 5873acd0-baa8 ssl://172.17.0.2:4567",
			inputCtx: types.LogCtx{
				OwnIPs:   []string{"172.17.0.2"},
				HashToIP: map[string]string{},
			},
			expectedCtx: types.LogCtx{
				OwnIPs:   []string{"172.17.0.2"},
				HashToIP: map[string]string{"5873acd0-baa8": "172.17.0.2"},
			},
			expectedOut:          "",
			displayerExpectedNil: true,
			mapToTest:            ViewsMap,
			key:                  "RegexNodeEstablished",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] declaring 5873acd0-baa8 at ssl://172.17.0.2:4567 stable",
			inputCtx: types.LogCtx{
				HashToIP:   map[string]string{},
				IPToMethod: map[string]string{},
			},
			expectedCtx: types.LogCtx{
				HashToIP:   map[string]string{"5873acd0-baa8": "172.17.0.2"},
				IPToMethod: map[string]string{"172.17.0.2": "ssl"},
			},
			expectedOut: "172.17.0.2 joined",
			mapToTest:   ViewsMap,
			key:         "RegexNodeJoined",
		},
		{
			name: "mariadb variation",
			log:  "2001-01-01  1:01:30 0 [Note] WSREP: declaring 5873acd0-baa8 at tcp://172.17.0.2:4567 stable",
			inputCtx: types.LogCtx{
				HashToIP:   map[string]string{},
				IPToMethod: map[string]string{},
			},
			expectedCtx: types.LogCtx{
				HashToIP:   map[string]string{"5873acd0-baa8": "172.17.0.2"},
				IPToMethod: map[string]string{"172.17.0.2": "tcp"},
			},
			expectedOut: "172.17.0.2 joined",
			mapToTest:   ViewsMap,
			key:         "RegexNodeJoined",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] forgetting 871c35de-99ae (ssl://172.17.0.2:4567)",
			expectedOut: "172.17.0.2 left",
			mapToTest:   ViewsMap,
			key:         "RegexNodeLeft",
		},

		{
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: New COMPONENT: primary = yes, bootstrap = no, my_idx = 0, memb_num = 2",
			expectedCtx:   types.LogCtx{MemberCount: 2},
			expectedState: "PRIMARY",
			expectedOut:   "PRIMARY(n=2)",
			mapToTest:     ViewsMap,
			key:           "RegexNewComponent",
		},
		{
			name:          "bootstrap",
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: New COMPONENT: primary = yes, bootstrap = yes, my_idx = 0, memb_num = 2",
			expectedCtx:   types.LogCtx{MemberCount: 2},
			expectedState: "PRIMARY",
			expectedOut:   "PRIMARY(n=2),bootstrap",
			mapToTest:     ViewsMap,
			key:           "RegexNewComponent",
		},
		{
			name:          "don't set primary",
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: New COMPONENT: primary = yes, bootstrap = no, my_idx = 0, memb_num = 2",
			inputState:    "JOINER",
			expectedCtx:   types.LogCtx{MemberCount: 2},
			expectedState: "JOINER",
			expectedOut:   "PRIMARY(n=2)",
			mapToTest:     ViewsMap,
			key:           "RegexNewComponent",
		},
		{
			name:          "non-primary",
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: New COMPONENT: primary = no, bootstrap = no, my_idx = 0, memb_num = 2",
			expectedCtx:   types.LogCtx{MemberCount: 2},
			expectedState: "NON-PRIMARY",
			expectedOut:   "NON-PRIMARY(n=2)",
			mapToTest:     ViewsMap,
			key:           "RegexNewComponent",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 84580 [Note] [MY-000000] [Galera] evs::proto(9a826787-9e98, LEAVING, view_id(REG,4971d113-87b0,22)) suspecting node: 4971d113-87b0",
			inputCtx: types.LogCtx{
				HashToIP: map[string]string{},
			},
			expectedCtx: types.LogCtx{
				HashToIP: map[string]string{},
			},
			expectedOut: "4971d113-87b0 suspected to be down",
			mapToTest:   ViewsMap,
			key:         "RegexNodeSuspect",
		},
		{
			name: "with known ip",
			log:  "2001-01-01T01:01:01.000000Z 84580 [Note] [MY-000000] [Galera] evs::proto(9a826787-9e98, LEAVING, view_id(REG,4971d113-87b0,22)) suspecting node: 4971d113-87b0",
			inputCtx: types.LogCtx{
				HashToIP: map[string]string{"4971d113-87b0": "172.17.0.2"},
			},
			expectedCtx: types.LogCtx{
				HashToIP: map[string]string{"4971d113-87b0": "172.17.0.2"},
			},
			expectedOut: "172.17.0.2 suspected to be down",
			mapToTest:   ViewsMap,
			key:         "RegexNodeSuspect",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: remote endpoint tcp://172.17.0.2:4567 changed identity 84953af9 -> 5a478da2",
			inputCtx: types.LogCtx{
				HashToIP: map[string]string{"84953af9": "172.17.0.2"},
			},
			expectedCtx: types.LogCtx{
				HashToIP: map[string]string{"84953af9": "172.17.0.2", "5a478da2": "172.17.0.2"},
			},
			expectedOut: "172.17.0.2 changed identity",
			mapToTest:   ViewsMap,
			key:         "RegexNodeChangedIdentity",
		},
		{
			name: "with complete uuid",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] remote endpoint ssl://172.17.0.2:4567 changed identity 595812bc-9c79-11ec-ad3f-3a7953bcc2fc -> 595812bc-9c79-11ec-ad40-3a7953bcc2fc",
			inputCtx: types.LogCtx{
				HashToIP: map[string]string{"595812bc-ad3f": "172.17.0.2"},
			},
			expectedCtx: types.LogCtx{
				HashToIP: map[string]string{"595812bc-ad3f": "172.17.0.2", "595812bc-ad40": "172.17.0.2"},
			},
			expectedOut: "172.17.0.2 changed identity",
			mapToTest:   ViewsMap,
			key:         "RegexNodeChangedIdentity",
		},

		{
			log:           "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [Galera] It may not be safe to bootstrap the cluster from this node. It was not the last one to leave the cluster and may not contain all the updates. To force cluster bootstrap with this node, edit the grastate.dat file manually and set safe_to_bootstrap to 1 .",
			expectedState: "CLOSED",
			expectedOut:   "not safe to bootstrap",
			mapToTest:     ViewsMap,
			key:           "RegexWsrepUnsafeBootstrap",
		},

		{
			log:           "2001-01-01T01:01:01.481967+09:00 4 [ERROR] WSREP: Node consistency compromised, aborting...",
			expectedState: "CLOSED",
			expectedOut:   "consistency compromised",
			mapToTest:     ViewsMap,
			key:           "RegexWsrepConsistenctyCompromised",
		},
		{
			log:           "2001-01-01T01:01:01.000000Z 86 [ERROR] WSREP: Node consistency compromized, aborting...",
			expectedState: "CLOSED",
			expectedOut:   "consistency compromised",
			mapToTest:     ViewsMap,
			key:           "RegexWsrepConsistenctyCompromised",
		},

		{
			log:         "2001-01-01  5:06:12 47285568576576 [Note] WSREP: gcomm: bootstrapping new group 'cluster'",
			expectedOut: "bootstrapping",
			mapToTest:   ViewsMap,
			key:         "RegexBootstrap",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Found saved state: 8e862473-455e-11e8-a0ca-3fcd8faf3209:-1, safe_to_bootstrap: 1",
			expectedOut: "safe_to_bootstrap: 1",
			mapToTest:   ViewsMap,
			key:         "RegexSafeToBoostrapSet",
		},
		{
			name:        "should not match",
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Found saved state: 8e862473-455e-11e8-a0ca-3fcd8faf3209:-1, safe_to_bootstrap: 0",
			expectedErr: true,
			mapToTest:   ViewsMap,
			key:         "RegexSafeToBoostrapSet",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Warning] [MY-000000] [Galera] Could not open state file for reading: '/var/lib/mysql//grastate.dat'",
			expectedOut: "no grastate.dat file",
			mapToTest:   ViewsMap,
			key:         "RegexNoGrastate",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Warning] [MY-000000] [Galera] No persistent state found. Bootstraping with default state",
			expectedOut: "bootstrapping(empty grastate)",
			mapToTest:   ViewsMap,
			key:         "RegexBootstrapingDefaultState",
		},

		{
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Shifting OPEN -> CLOSED (TO: 1922878)",
			expectedState: "CLOSED",
			expectedOut:   "OPEN -> CLOSED",
			mapToTest:     StatesMap,
			key:           "RegexShift",
		},
		{
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Shifting SYNCED -> DONOR/DESYNCED (TO: 21582507)",
			expectedState: "DONOR",
			expectedOut:   "SYNCED -> DONOR",
			mapToTest:     StatesMap,
			key:           "RegexShift",
		},
		{
			log:           "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Shifting DONOR/DESYNCED -> JOINED (TO: 21582507)",
			expectedState: "JOINED",
			expectedOut:   "DESYNCED -> JOINED",
			mapToTest:     StatesMap,
			key:           "RegexShift",
		},

		{
			log:           "2001-01-01 01:01:01 140446385440512 [Note] WSREP: Restored state OPEN -> SYNCED (72438094)",
			expectedState: "SYNCED",
			expectedOut:   "(restored)OPEN -> SYNCED",
			mapToTest:     StatesMap,
			key:           "RegexRestoredState",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Member 2.0 (node2) requested state transfer from '*any*'. Selected 0.0 (node1)(SYNCED) as donor.",
			inputCtx:    types.LogCtx{SSTs: map[string]types.SST{}},
			expectedCtx: types.LogCtx{SSTs: map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", SelectionTimestamp: timeMustParse("2001-01-01T01:01:01.000000Z")}}},
			expectedOut: "node1 will resync node2",
			mapToTest:   SSTMap,
			key:         "RegexSSTRequestSuccess",
		},
		{
			name:        "with fqdn",
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 2.0 (node2.host.com) requested state transfer from '*any*'. Selected 0.0 (node1.host.com)(SYNCED) as donor.",
			inputCtx:    types.LogCtx{SSTs: map[string]types.SST{}},
			expectedCtx: types.LogCtx{SSTs: map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", SelectionTimestamp: timeMustParse("2001-01-01T01:01:01.000000Z")}}},
			expectedOut: "node1 will resync node2",
			mapToTest:   SSTMap,
			key:         "RegexSSTRequestSuccess",
		},
		{
			name: "joining",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Member 2.0 (node2) requested state transfer from '*any*'. Selected 0.0 (node1)(SYNCED) as donor.",
			inputCtx: types.LogCtx{
				OwnNames: []string{"node2"},
				SSTs:     map[string]types.SST{},
			},
			expectedCtx: types.LogCtx{
				OwnNames: []string{"node2"},
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", SelectionTimestamp: timeMustParse("2001-01-01T01:01:01.000000Z")}},
			},
			expectedOut: "node1 will resync local node",
			mapToTest:   SSTMap,
			key:         "RegexSSTRequestSuccess",
		},
		{
			name: "donor",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Member 2.0 (node2) requested state transfer from '*any*'. Selected 0.0 (node1)(SYNCED) as donor.",
			inputCtx: types.LogCtx{
				OwnNames: []string{"node1"},
				SSTs:     map[string]types.SST{},
			},
			expectedCtx: types.LogCtx{
				OwnNames: []string{"node1"},
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", SelectionTimestamp: timeMustParse("2001-01-01T01:01:01.000000Z")}},
			},
			expectedOut: "local node will resync node2",
			mapToTest:   SSTMap,
			key:         "RegexSSTRequestSuccess",
		},

		{
			log:         "2001-01-01 01:01:01.164  WARN: Member 1.0 (node2) requested state transfer from 'node1', but it is impossible to select State Transfer donor: Resource temporarily unavailable",
			inputCtx:    types.LogCtx{},
			expectedCtx: types.LogCtx{},
			expectedOut: "node2 cannot find donor",
			mapToTest:   SSTMap,
			key:         "RegexSSTResourceUnavailable",
		},
		{
			name: "local",
			log:  "2001-01-01 01:01:01.164  WARN: Member 1.0 (node2) requested state transfer from 'node1', but it is impossible to select State Transfer donor: Resource temporarily unavailable",
			inputCtx: types.LogCtx{
				OwnNames: []string{"node2"},
			},
			expectedCtx: types.LogCtx{
				OwnNames: []string{"node2"},
			},
			expectedOut: "cannot find donor",
			mapToTest:   SSTMap,
			key:         "RegexSSTResourceUnavailable",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to 2.0 (node2) complete.",
			inputCtx: types.LogCtx{
				SSTs: map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
			},
			expectedCtx: types.LogCtx{
				SSTs: map[string]types.SST{},
			},
			expectedOut: "node1 synced node2",
			mapToTest:   SSTMap,
			key:         "RegexSSTComplete",
		},
		{
			name: "joiner",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to 2.0 (node2) complete.",
			inputCtx: types.LogCtx{
				OwnNames: []string{"node2"},
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{},
				OwnNames: []string{"node2"},
			},
			expectedOut: "got SST from node1",
			mapToTest:   SSTMap,
			key:         "RegexSSTComplete",
		},
		{
			name: "joiner ist",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to 2.0 (node2) complete.",
			inputCtx: types.LogCtx{
				OwnNames: []string{"node2"},
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{},
				OwnNames: []string{"node2"},
			},
			expectedOut: "got IST from node1",
			mapToTest:   SSTMap,
			key:         "RegexSSTComplete",
		},
		{
			name: "donor",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to 2.0 (node2) complete.",
			inputCtx: types.LogCtx{
				OwnNames: []string{"node1"},
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{},
				OwnNames: []string{"node1"},
			},
			expectedOut: "finished sending SST to node2",
			mapToTest:   SSTMap,
			key:         "RegexSSTComplete",
		},
		{
			name: "donor ist",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to 2.0 (node2) complete.",
			inputCtx: types.LogCtx{
				OwnNames: []string{"node1"},
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{},
				OwnNames: []string{"node1"},
			},
			expectedOut: "finished sending IST to node2",
			mapToTest:   SSTMap,
			key:         "RegexSSTComplete",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: 0.0 (node1): State transfer to -1.-1 (left the group) complete.",
			inputCtx:    types.LogCtx{},
			expectedCtx: types.LogCtx{},
			expectedOut: "node1 synced ??(node left)",
			mapToTest:   SSTMap,
			key:         "RegexSSTCompleteUnknown",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [WSREP] Process completed with error: wsrep_sst_xtrabackup-v2 --role 'donor' --address '172.17.0.2:4444/xtrabackup_sst//1' --socket '/var/lib/mysql/mysql.sock' --datadir '/var/lib/mysql/' --basedir '/usr/' --plugindir '/usr/lib64/mysql/plugin/' --defaults-file '/etc/my.cnf' --defaults-group-suffix '' --mysqld-version '8.0.28-19.1'   '' --gtid '9db0bcdf-b31a-11ed-a398-2a4cfdd82049:1' : 22 (Invalid argument)",
			expectedOut: "SST error",
			mapToTest:   SSTMap,
			key:         "RegexSSTError",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 1328586 [Note] [MY-000000] [WSREP] Initiating SST cancellation",
			expectedOut: "former SST cancelled",
			mapToTest:   SSTMap,
			key:         "RegexSSTCancellation",
		},

		{
			log: "2001-01-01T01:01:01.000000Z WSREP_SST: [INFO] Proceeding with SST.........",
			inputCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				OwnNames: []string{"node2"},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "SST"}},
				OwnNames: []string{"node2"},
			},
			expectedState: "JOINER",
			expectedOut:   "receiving SST",
			mapToTest:     SSTMap,
			key:           "RegexSSTProceeding",
		},

		{
			log:           "2001-01-01T01:01:01.000000Z WSREP_SST: [INFO] Streaming the backup to joiner at 172.17.0.2 4444",
			expectedState: "DONOR",
			expectedOut:   "SST to 172.17.0.2",
			mapToTest:     SSTMap,
			key:           "RegexSSTStreamingTo",
		},

		{
			log:         "2001-01-01 01:01:01 140446376740608 [Note] WSREP: IST received: e00c4fff-c4b0-11e9-96a8-0f9789de42ad:69472531",
			expectedCtx: types.LogCtx{},
			expectedOut: "IST received(seqno:69472531)",
			mapToTest:   SSTMap,
			key:         "RegexISTReceived",
		},

		{
			log: "2001-01-01  1:01:01 140433613571840 [Note] WSREP: async IST sender starting to serve tcp://172.17.0.2:4568 sending 2-116",
			inputCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				OwnNames: []string{"node1"},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
				OwnNames: []string{"node1"},
			},
			expectedState: "DONOR",
			expectedOut:   "IST to 172.17.0.2(seqno:116)",
			mapToTest:     SSTMap,
			key:           "RegexISTSender",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Prepared IST receiver for 114-116, listening at: ssl://172.17.0.2:4568",
			inputCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				OwnNames: []string{"node2"},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
				OwnNames: []string{"node2"},
			},
			expectedState: "JOINER",
			expectedOut:   "will receive IST(seqno:116)",
			mapToTest:     SSTMap,
			key:           "RegexISTReceiver",
		},
		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Prepared IST receiver for 0-116, listening at: ssl://172.17.0.2:4568",
			inputCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				OwnNames: []string{"node2"},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "SST"}},
				OwnNames: []string{"node2"},
			},
			expectedState: "JOINER",
			expectedOut:   "will receive SST",
			mapToTest:     SSTMap,
			key:           "RegexISTReceiver",
		},
		{
			name: "mdb variant",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Prepared IST receiver, listening at: ssl://172.17.0.2:4568",
			inputCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				OwnNames: []string{"node2"},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
				OwnNames: []string{"node2"},
			},
			expectedState: "JOINER",
			expectedOut:   "will receive IST",
			mapToTest:     SSTMap,
			key:           "RegexISTReceiver",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Warning] [MY-000000] [Galera] 0.1 (node): State transfer to -1.-1 (left the group) failed: -111 (Connection refused)",
			expectedOut: "node failed to sync ??(node left)",
			mapToTest:   SSTMap,
			key:         "RegexSSTFailedUnknown",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Warning] [MY-000000] [Galera] 0.1 (node): State transfer to 0.2 (node2) failed: -111 (Connection refused)",
			expectedOut: "node failed to sync node2",
			mapToTest:   SSTMap,
			key:         "RegexSSTStateTransferFailed",
		},
		{
			log:                  "2001-01-01T01:01:01.000000Z 0 [Warning] [MY-000000] [Galera] 0.1 (node): State transfer to -1.-1 (left the group) failed: -111 (Connection refused)",
			displayerExpectedNil: true,
			mapToTest:            SSTMap,
			key:                  "RegexSSTStateTransferFailed",
		},

		{
			log:        "2001-01-01T01:01:01.000000Z 1 [Note] WSREP: Failed to prepare for incremental state transfer: Local state UUID (00000000-0000-0000-0000-000000000000) does not match group state UUID (ed16c932-84b3-11ed-998c-8e3ae5bc328f): 1 (Operation not permitted)",
			inputState: "JOINER",
			inputCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				OwnNames: []string{"node2"},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "SST"}},
				OwnNames: []string{"node2"},
			},
			expectedState: "JOINER",
			expectedOut:   "IST is not applicable",
			mapToTest:     SSTMap,
			key:           "RegexFailedToPrepareIST",
		},
		{
			log:        "2001-01-01T01:01:01.000000Z 1 [Warning] WSREP: Failed to prepare for incremental state transfer: Local state seqno is undefined: 1 (Operation not permitted)",
			inputState: "JOINER",
			inputCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				OwnNames: []string{"node2"},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "SST"}},
				OwnNames: []string{"node2"},
			},
			expectedState: "JOINER",
			expectedOut:   "IST is not applicable",
			mapToTest:     SSTMap,
			key:           "RegexFailedToPrepareIST",
		},

		{
			log:        "2001-01-01T01:01:01.000000Z WSREP_SST: [INFO] Bypassing SST. Can work it through IST",
			inputState: "JOINER",
			inputCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				OwnNames: []string{"node2"},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
				OwnNames: []string{"node2"},
			},
			expectedState: "JOINER",
			expectedOut:   "IST will be used",
			mapToTest:     SSTMap,
			key:           "RegexBypassSST",
		},

		{
			log:        "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [WSREP-SST] xtrabackup_ist received from donor: Running IST",
			inputState: "JOINER",
			inputCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2"}},
				OwnNames: []string{"node2"},
			},
			expectedCtx: types.LogCtx{
				SSTs:     map[string]types.SST{"node1": types.SST{Donor: "node1", Joiner: "node2", Type: "IST"}},
				OwnNames: []string{"node2"},
			},
			expectedState: "JOINER",
			expectedOut:   "IST running",
			mapToTest:     SSTMap,
			key:           "RegexXtrabackupISTReceived",
		},

		{
			log:         "2001/01/01 01:01:01 socat[23579] E connect(62, AF=2 172.17.0.20:4444, 16): Connection refused",
			expectedOut: "socat: connection refused",
			mapToTest:   SSTMap,
			key:         "RegexSocatConnRefused",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [WSREP-SST] Preparing the backup at /var/lib/mysql/sst-xb-tmpdir",
			expectedOut: "preparing SST backup",
			mapToTest:   SSTMap,
			key:         "RegexPreparingBackup",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z WSREP_SST: [ERROR] Possible timeout in receving first data from donor in gtid/keyring stage",
			expectedOut: "timeout from donor in gtid/keyring stage",
			mapToTest:   SSTMap,
			key:         "RegexTimeoutReceivingFirstData",
		},

		{
			log:         "2001-01-01 01:01:01 140666176771840 [ERROR] WSREP: gcs/src/gcs_group.cpp:gcs_group_handle_join_msg():736: Will never receive state. Need to abort.",
			expectedOut: "will never receive SST, aborting",
			mapToTest:   SSTMap,
			key:         "RegexWillNeverReceive",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [ERROR] WSREP: async IST sender failed to serve tcp://172.17.0.2:4568: ist send failed: asio.system:32', asio error 'write: Broken pipe': 32 (Broken pipe)",
			expectedOut: "IST to 172.17.0.2 failed: Broken pipe",
			mapToTest:   SSTMap,
			key:         "RegexISTFailed",
		},
		{
			log:         "2001-01-01 01:10:01 28949 [ERROR] WSREP: async IST sender failed to serve tcp://172.17.0.2:4568: ist send failed: asio.system:104', asio error 'write: Connection reset by peer': 104 (Connection reset by peer)",
			expectedOut: "IST to 172.17.0.2 failed: Connection reset by peer",
			mapToTest:   SSTMap,
			key:         "RegexISTFailed",
		},
		{
			log:         "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [Galera] async IST sender failed to serve ssl://172.17.0.2:4568: ist send failed: ', asio error 'Got unexpected return from write: eof: 71 (Protocol error)",
			expectedOut: "IST to 172.17.0.2 failed: Protocol error",
			mapToTest:   SSTMap,
			key:         "RegexISTFailed",
		},
		{
			log:         `{\"log\":\"2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [Galera] async IST sender failed to serve ssl://172.17.0.2:4568: ist send failed: ', asio error 'Got unexpected return from write: eof: 71 (Protocol error)\n\t at galerautils/src/gu_asio_stream_react.cpp:write():195': 71 (Protocol error)\n\t at galera/src/ist.cpp:send():856\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}`,
			expectedOut: "IST to 172.17.0.2 failed: Protocol error",
			mapToTest:   SSTMap,
			key:         "RegexISTFailed",
		},

		{
			log:         "+ NODE_NAME=cluster1-pxc-0.cluster1-pxc.test-percona.svc.cluster.local",
			expectedCtx: types.LogCtx{OwnNames: []string{"cluster1-pxc-0"}},
			expectedOut: "local name:cluster1-pxc-0",
			mapToTest:   PXCOperatorMap,
			key:         "RegexNodeNameFromEnv",
		},

		{
			log:         "+ NODE_IP=172.17.0.2",
			expectedCtx: types.LogCtx{OwnIPs: []string{"172.17.0.2"}},
			expectedOut: "local ip:172.17.0.2",
			mapToTest:   PXCOperatorMap,
			key:         "RegexNodeIPFromEnv",
		},

		{
			log:         "{\"log\":\"2023-07-05T08:17:23.447015Z 0 [Note] [MY-000000] [Galera] GCache::RingBuffer initial scan...  0.0% (         0/1073741848 bytes) complete.\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			expectedOut: "recovering gcache",
			mapToTest:   PXCOperatorMap,
			key:         "RegexGcacheScan",
		},

		{
			log:         "2001-01-01  1:01:01 0 [Note] WSREP: Member 0.0 (node) desyncs itself from group",
			expectedCtx: types.LogCtx{Desynced: true},
			expectedOut: "node desyncs itself from group",
			mapToTest:   ApplicativeMap,
			key:         "RegexDesync",
		},

		{
			log:         "2001-01-01  1:01:01 0 [Note] WSREP: Member 0.0 (node) resyncs itself to group",
			expectedCtx: types.LogCtx{Desynced: false},
			inputCtx:    types.LogCtx{Desynced: true},
			expectedOut: "node resyncs itself to group",
			mapToTest:   ApplicativeMap,
			key:         "RegexResync",
		},

		{
			log:         "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 1(node1) initiates vote on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,bdb2b9234ae75cb3:  some error, Error_code: 123;\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			expectedOut: "inconsistency vote started by node1(seqno:20)",
			expectedCtx: types.LogCtx{Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			mapToTest:   ApplicativeMap,
			key:         "RegexInconsistencyVoteInit",
		},
		{
			log:         "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 1(node1) initiates vote on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,bdb2b9234ae75cb3:  some error, Error_code: 123;\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			inputCtx:    types.LogCtx{OwnNames: []string{"node1"}},
			expectedCtx: types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			expectedOut: "inconsistency vote started(seqno:20)",
			mapToTest:   ApplicativeMap,
			key:         "RegexInconsistencyVoteInit",
		},

		{
			log:         "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 2(node2) responds to vote on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,0000000000000000: Success\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			inputCtx:    types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			expectedCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "0000000000000000", Error: "Success"}}}}},
			expectedOut: "consistency vote(seqno:20): voted Success",
			mapToTest:   ApplicativeMap,
			key:         "RegexInconsistencyVoteRespond",
		},
		{
			log:         "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 2(node2) responds to vote on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,bdb2b9234ae75cb3: some error\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			inputCtx:    types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			expectedCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			expectedOut: "consistency vote(seqno:20): voted same error",
			mapToTest:   ApplicativeMap,
			key:         "RegexInconsistencyVoteRespond",
		},
		{
			// could not actually find a "responds to" with any error for now
			log:         "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 2(node2) responds to vote on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,ed9774a3cad44656: some different error\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			inputCtx:    types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			expectedCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "ed9774a3cad44656", Error: "some different error"}}}}},
			expectedOut: "consistency vote(seqno:20): voted different error",
			mapToTest:   ApplicativeMap,
			key:         "RegexInconsistencyVoteRespond",
		},

		{
			log:         "{\"log\":\"2001-01-01T01:01:01.000000Z 1 [ERROR] [MY-000000] [Galera] Inconsistency detected: Inconsistent by consensus on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:127\n\t at galera/src/replicator_smm.cpp:process_apply_error():1469\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			expectedOut: "found inconsistent by vote",
			mapToTest:   ApplicativeMap,
			key:         "RegexInconsistencyVoted",
		},

		{
			log:         "Winner: bdb2b9234ae75cb3",
			inputCtx:    types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			expectedCtx: types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			expectedOut: "consistency vote(seqno:20): won",
			mapToTest:   ApplicativeMap,
			key:         "RegexInconsistencyWinner",
		},
		{
			log:         "Winner: 0000000000000000",
			inputCtx:    types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "0000000000000000", Error: "Success"}}}}},
			expectedCtx: types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "0000000000000000", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "0000000000000000", Error: "Success"}}}}},
			expectedOut: "consistency vote(seqno:20): lost",
			mapToTest:   ApplicativeMap,
			key:         "RegexInconsistencyWinner",
		},
		{
			name:                 "already voted conflict, should not print anything",
			log:                  "Winner: 0000000000000000",
			inputCtx:             types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			expectedCtx:          types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			displayerExpectedNil: true,
			mapToTest:            ApplicativeMap,
			key:                  "RegexInconsistencyWinner",
		},

		{
			log:         "{\"log\":\"2001-01-01T01:01:01.000000Z 1 [ERROR] [MY-000000] [Galera] Recovering vote result from history: 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,bdb2b9234ae75cb3\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			inputCtx:    types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			expectedCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "bdb2b9234ae75cb3"}}}}},
			expectedOut: "consistency vote(seqno:20): voted same error",
			mapToTest:   ApplicativeMap,
			key:         "RegexInconsistencyRecovery",
		},
		{
			log:         "{\"log\":\"2001-01-01T01:01:01.000000Z 1 [ERROR] [MY-000000] [Galera] Recovering vote result from history: 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,0000000000000000\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			inputCtx:    types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			expectedCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "0000000000000000"}}}}},
			expectedOut: "consistency vote(seqno:20): voted Success",
			mapToTest:   ApplicativeMap,
			key:         "RegexInconsistencyRecovery",
		},
	}

	for _, test := range tests {
		if test.name == "" {
			test.name = "default"
		}
		if _, ok := test.mapToTest[test.key]; !ok {
			t.Fatalf("key %s does not exist in maps", test.key)
		}
		err := testRegexFromMap(t, test.log, test.mapToTest[test.key])
		if err != nil {
			if test.expectedErr {
				continue
			}
			t.Fatalf("key: %s\ntestname: %s\nregex string: \"%s\"\nlog: %s\n", test.key, test.name, test.mapToTest[test.key].Regex.String(), err)
		}

		if test.inputState != "" {
			test.inputCtx.SetState(test.inputState)
		}

		ctx, displayer := test.mapToTest[test.key].Handle(test.inputCtx, test.log)
		msg := ""
		if displayer != nil {
			msg = displayer(ctx)
		} else if !test.displayerExpectedNil {
			t.Errorf("key: %s\ntestname: %s\ndisplayer is nil\nexpected: not nil", test.key, test.name)
		}

		// alternative to reflect.deepequal, it enables to avoid comparing "states" map
		res := cmp.Equal(ctx, test.expectedCtx, cmpopts.IgnoreUnexported(types.LogCtx{}))
		if !res || msg != test.expectedOut || ctx.State() != test.expectedState {
			t.Errorf("\nkey: %s\ntestname: %s\nctx: %+v\nexpected ctx: %+v\nout: %s\nexpected out: %s\nstate: %s\nexpected state: %s", test.key, test.name, spew.Sdump(ctx), spew.Sdump(test.expectedCtx), msg, test.expectedOut, ctx.State(), test.expectedState)
			t.Fail()
		}
	}
}

func timeMustParse(s string) *time.Time {
	t, _, _ := SearchDateFromLog(s)
	return &t
}

func testRegexFromMap(t *testing.T, log string, regex *types.LogRegex) error {
	m := types.RegexMap{"test": regex}

	return testActualGrepOnLog(t, log, m.Compile()[0])
}

func testActualGrepOnLog(t *testing.T, log, regex string) error {

	f, err := ioutil.TempFile(t.TempDir(), "test_log")
	if err != nil {
		return errors.Wrap(err, "failed to create tmp file")
	}
	defer f.Sync()

	_, err = f.WriteString(log)
	if err != nil {
		return errors.Wrap(err, "failed to write in tmp file")
	}

	out, err := exec.Command("grep", "-P", regex, f.Name()).Output()
	if err != nil {
		return errors.Wrap(err, "failed to grep in tmp file")
	}
	if string(out) == "" {
		return errors.Wrap(err, "empty results when grepping in tmp file")
	}
	return nil
}
