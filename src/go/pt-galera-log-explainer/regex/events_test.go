package regex

import (
	"testing"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
)

func TestEventsRegex(t *testing.T) {
	tests := []regexTest{
		{
			name: "8.0.30-22",
			log:  "2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 8.0.30-22) starting as process 1",
			expected: regexTestState{
				Ctx:   types.LogCtx{Version: "8.0.30"},
				State: "OPEN",
			},
			expectedOut: "starting(8.0.30)",
			key:         "RegexStarting",
		},
		{
			name: "8.0.2-22",
			log:  "2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 8.0.2-22) starting as process 1",
			expected: regexTestState{
				Ctx:   types.LogCtx{Version: "8.0.2"},
				State: "OPEN",
			},
			expectedOut: "starting(8.0.2)",
			key:         "RegexStarting",
		},
		{
			name: "5.7.31-34-log",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] /usr/sbin/mysqld (mysqld 5.7.31-34-log) starting as process 2 ...",
			expected: regexTestState{
				Ctx:   types.LogCtx{Version: "5.7.31"},
				State: "OPEN",
			},
			expectedOut: "starting(5.7.31)",
			key:         "RegexStarting",
		},
		{
			name: "10.4.25-MariaDB-log",
			log:  "2001-01-01  01:01:01 0 [Note] /usr/sbin/mysqld (mysqld 10.4.25-MariaDB-log) starting as process 2 ...",
			expected: regexTestState{
				Ctx:   types.LogCtx{Version: "10.4.25"},
				State: "OPEN",
			},
			expectedOut: "starting(10.4.25)",
			key:         "RegexStarting",
		},
		{
			name: "10.2.31-MariaDB-1:10.2.31+maria~bionic-log",
			log:  "2001-01-01  01:01:01 0 [Note] /usr/sbin/mysqld (mysqld 10.2.31-MariaDB-1:10.2.31+maria~bionic-log) starting as process 2 ...",
			expected: regexTestState{
				Ctx:   types.LogCtx{Version: "10.2.31"},
				State: "OPEN",
			},
			expectedOut: "starting(10.2.31)",
			key:         "RegexStarting",
		},
		{
			name: "5.7.28-enterprise-commercial-advanced-log",
			log:  "2001-01-01T01:01:01.000000Z 0 [Note] /usr/sbin/mysqld (mysqld 5.7.28-enterprise-commercial-advanced-log) starting as process 2 ...",
			expected: regexTestState{
				Ctx:   types.LogCtx{Version: "5.7.28"},
				State: "OPEN",
			},
			expectedOut: "starting(5.7.28)",
			key:         "RegexStarting",
		},
		{
			name: "8.0.30 operator",
			log:  "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 8.0.30-22.1) starting as process 1\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			expected: regexTestState{
				Ctx:   types.LogCtx{Version: "8.0.30"},
				State: "OPEN",
			},
			expectedOut: "starting(8.0.30)",
			key:         "RegexStarting",
		},
		{
			name:                 "wrong version 7.0.0",
			log:                  "2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 7.0.0-22) starting as process 1",
			displayerExpectedNil: true,
			key:                  "RegexStarting",
		},
		{
			name:                 "wrong version 8.12.0",
			log:                  "2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 8.12.0-22) starting as process 1",
			displayerExpectedNil: true,
			key:                  "RegexStarting",
		},
		{
			name: "could not catch how it stopped",
			log:  "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [System] [MY-010116] [Server] /usr/sbin/mysqld (mysqld 8.0.30-22.1) starting as process 1\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			expected: regexTestState{
				Ctx:   types.LogCtx{Version: "8.0.30"},
				State: "OPEN",
			},
			input: regexTestState{
				State: "OPEN",
			},
			expectedOut: "starting(8.0.30, could not catch how/when it stopped)",
			key:         "RegexStarting",
		},

		{

			log: "2001-01-01T01:01:01.000000Z 0 [System] [MY-010910] [Server] /usr/sbin/mysqld: Shutdown complete (mysqld 8.0.23-14.1)  Percona XtraDB Cluster (GPL), Release rel14, Revision d3b9a1d, WSREP version 26.4.3.",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "shutdown complete",
			key:         "RegexShutdownComplete",
		},

		{
			log: "2001-01-01 01:01:01 140430087788288 [Note] WSREP: /opt/rh-mariadb102/root/usr/libexec/mysqld: Terminated.",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "terminated",
			key:         "RegexTerminated",
		},
		{
			log: "2001-01-01T01:01:01.000000Z 8 [Note] WSREP: /usr/sbin/mysqld: Terminated.",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "terminated",
			key:         "RegexTerminated",
		},

		{
			log: "01:01:01 UTC - mysqld got signal 6 ;",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "crash: got signal 6",
			key:         "RegexGotSignal6",
		},
		{
			log: "01:01:01 UTC - mysqld got signal 11 ;",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "crash: got signal 11",
			key:         "RegexGotSignal11",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [WSREP] Received shutdown signal. Will sleep for 10 secs before initiating shutdown. pxc_maint_mode switched to SHUTDOWN",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "received shutdown",
			key:         "RegexShutdownSignal",
		},
		{
			log: "2001-01-01 01:01:01 139688443508480 [Note] /opt/rh-mariadb102/root/usr/libexec/mysqld (unknown): Normal shutdown",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "received shutdown",
			key:         "RegexShutdownSignal",
		},
		{
			log: "2001-01-01  1:01:01 0 [Note] /usr/sbin/mariadbd (initiated by: unknown): Normal shutdown",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "received shutdown",
			key:         "RegexShutdownSignal",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-010119] [Server] Aborting",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "ABORTING",
			key:         "RegexAborting",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] wsrep_load(): loading provider library '/usr/lib64/galera4/libgalera_smm.so'",
			expected: regexTestState{
				State: "OPEN",
			},
			expectedOut: "started(cluster)",
			key:         "RegexWsrepLoad",
		},
		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] wsrep_load(): loading provider library 'none'",
			expected: regexTestState{
				State: "OPEN",
			},
			expectedOut: "started(standalone)",
			key:         "RegexWsrepLoad",
		},

		{
			log: "2001-01-01 01:01:01 140557650536640 [Note] WSREP: wsrep_load(): loading provider library '/opt/rh-mariadb102/root/usr/lib64/galera/libgalera_smm.so'",
			expected: regexTestState{
				State: "OPEN",
			},
			expectedOut: "started(cluster)",
			key:         "RegexWsrepLoad",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 3 [Note] [MY-000000] [Galera] Recovered position from storage: 7780bb61-87cf-11eb-b53b-6a7c64b0fee3:23506640",
			expected: regexTestState{
				State: "RECOVERY",
			},
			expectedOut: "wsrep recovery",
			key:         "RegexWsrepRecovery",
		},
		{
			log: " INFO: WSREP: Recovered position 9a4db4a5-5cf1-11ec-940d-6ba8c5905c02:30",
			expected: regexTestState{
				State: "RECOVERY",
			},
			expectedOut: "wsrep recovery",
			key:         "RegexWsrepRecovery",
		},
		{
			log: " INFO: WSREP: Recovered position 00000000-0000-0000-0000-000000000000:-1",
			expected: regexTestState{
				State: "RECOVERY",
			},
			expectedOut: "wsrep recovery",
			key:         "RegexWsrepRecovery",
		},
		{
			name: "not unknown",
			log:  " INFO: WSREP: Recovered position 00000000-0000-0000-0000-000000000000:-1",
			expected: regexTestState{
				State: "RECOVERY",
			},
			input: regexTestState{
				State: "OPEN",
			},
			expectedOut: "wsrep recovery",
			key:         "RegexWsrepRecovery",
		},
		{
			name: "could not catch how it stopped",
			log:  " INFO: WSREP: Recovered position 00000000-0000-0000-0000-000000000000:-1",
			expected: regexTestState{
				State: "RECOVERY",
			},
			input: regexTestState{
				State: "SYNCED",
			},
			expectedOut: "wsrep recovery(could not catch how/when it stopped)",
			key:         "RegexWsrepRecovery",
		},

		{
			log:         "2001-01-01T01:01:01.045425-05:00 0 [ERROR] unknown variable 'validate_password_length=8'",
			expectedOut: "unknown variable: validate_password_le...",
			key:         "RegexUnknownConf",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-013183] [InnoDB] Assertion failure: btr0cur.cc:296:btr_page_get_prev(get_block->frame, mtr) == page_get_page_no(page) thread 139538894652992",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "ASSERTION FAILURE",
			key:         "RegexAssertionFailure",
		},

		{
			log: "2001-01-01  5:06:12 47285568576576 [ERROR] WSREP: failed to open gcomm backend connection: 98: error while trying to listen 'tcp://0.0.0.0:4567?socket.non_blocking=1', asio error 'bind: Address already in use': 98 (Address already in use)",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "bind address already used",
			key:         "RegexBindAddressAlreadyUsed",
		},

		{
			log:         "2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [Galera] gcs/src/gcs_group.cpp:group_post_state_exchange():431: Reversing history: 150 -> 10, this member has applied 140 more events than the primary component.Data loss is possible. Must abort.",
			expectedOut: "having 140 more events than the other nodes, data loss possible",
			key:         "RegexReversingHistory",
		},
	}

	iterateRegexTest(t, EventsMap, tests)
}
