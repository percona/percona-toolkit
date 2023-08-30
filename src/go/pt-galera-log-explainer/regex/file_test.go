package regex

import (
	"testing"
)

func TestFileType(t *testing.T) {
	tests := []struct {
		inputline     string
		inputoperator bool
		expected      string
	}{
		{
			inputline:     `{"log":"2023-07-11T06:03:51.109165Z 0 [Note] [MY-010747] [Server] Plugin 'FEDERATED' is disabled.\n","file":"/var/lib/mysql/wsrep_recovery_verbose.log"}`,
			inputoperator: true,
			expected:      "recovery.log",
		},
		{
			inputline:     `{"log":"2023-07-11T06:03:51.109165Z 0 [Note] [MY-010747] [Server] Plugin 'FEDERATED' is disabled.\n","file":"/var/lib/mysql/mysqld-error.log"}`,
			inputoperator: true,
			expected:      "error.log",
		},
		{
			inputline:     `{"log":"2023-07-11T06:03:51.109165Z 0 [Note] [MY-010747] [Server] Plugin 'FEDERATED' is disabled.\n","file":"/var/lib/mysql/mysqld.post.processing.log"}`,
			inputoperator: true,
			expected:      "post.processing.log",
		},
		{
			inputline:     `+ NODE_PORT=3306`,
			inputoperator: true,
			expected:      "operator shell",
		},
		{
			inputline:     `++ hostname -f`,
			inputoperator: true,
			expected:      "operator shell",
		},
	}

	for _, test := range tests {

		out := FileType(test.inputline, test.inputoperator)
		if out != test.expected {
			t.Errorf("expected: %s, got: %s", test.expected, out)
		}
	}
}
