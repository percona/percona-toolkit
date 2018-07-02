package sanitize

import (
	"reflect"
	"testing"

	"github.com/kr/pretty"
)

func TestSanitizeHostnames(t *testing.T) {

	want := []string{
		"top - 20:05:17 up 10 days, 16:27, 1 user, load average: 0.01, 0.15, 0.19",
		"Tasks: 115 total, 1 running, 114 sleeping, 0 stopped, 0 zombie",
		"%Cpu(s): 1.0 us, 0.3 sy, 0.0 ni, 98.6 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st",
		"KiB Mem : 3881748 total, 147324 free, 1892824 used, 1841600 buff/cache",
		"KiB Swap: 1572860 total, 1572748 free, 112 used. 1609372 avail Mem",
		"",
		"PID USER PR NI VIRT RES SHR S %CPU %MEM TIME+ COMMAND",
		"5304 vagrant 20 0 1983280 1.327g 12272 S 2.3 35.8 456:34.90 prometheus",
		"5313 root 20 0 142100 16952 5428 S 1.0 0.4 189:16.81 node_exporter		",
	}
	lines := make([]string, len(want))
	copy(lines, want)
	sanitizeHostnames(lines)
	if !reflect.DeepEqual(lines, want) {
		pretty.Println(want)
		pretty.Println(lines)
		t.Error("structures don't match")
	}

	lines = []string{
		"top - 20:05:17 up 10 days, 16:27, 1 user, load average: 0.01, 0.15, 0.19",
		"Tasks: 115 total, 1 running, 114 sleeping, 0 stopped, 0 zombie",
		"%Cpu(s): 1.0 us, 0.3 sy, 0.0 ni, 98.6 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st",
		"lets put a host name here: domain.com",
		"and put an ip address here: 10.0.0.1",
		"and put a non ip address here: 10.0",
	}
	want = []string{
		"top - 20:05:17 up 10 days, 16:27, 1 user, load average: 0.01, 0.15, 0.19",
		"Tasks: 115 total, 1 running, 114 sleeping, 0 stopped, 0 zombie",
		"%Cpu(s): 1.0 us, 0.3 sy, 0.0 ni, 98.6 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st",
		"lets put a host name here: hostname",
		"and put an ip address here: hostname",
		"and put a non ip address here: 10.0",
	}
	sanitizeHostnames(lines)
	if !reflect.DeepEqual(lines, want) {
		t.Error("structures don't match")
		pretty.Println(want)
		pretty.Println(lines)
	}
}
