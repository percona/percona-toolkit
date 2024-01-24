package sanitize

import (
	"regexp"
	"strings"

	"github.com/percona/go-mysql/query"
)

var (
	hostnameRE    = regexp.MustCompile(`(([a-zA-Z0-9]|[a-zA-Z0-9\-]*[a-zA-Z0-9])\.)+([A-Za-z]+)|([0-9]{1,3}\.){3}[0-9]{1,3}`)
	queryLineRe   []*regexp.Regexp
	queryInLineRe []*regexp.Regexp
)

func init() {
	statements := []string{
		"CREATE (TABLE|VIEW|DEFINER)",
		"DROP (DATABASE|TABLE|VIEW|DEFINER)",
		"INSERT INTO",
		"REPLACE INTO",
		"UPDATE",
		"SELECT.*FROM.*",
		"SET ",
		"SHOW TABLES",
		"SHOW DATABASES",
		"COMMIT",
		"LOAD DATA",
	}
	for _, re := range statements {
		queryLineRe = append(queryLineRe, regexp.MustCompile("(?i)^"+re))
		queryInLineRe = append(queryInLineRe, regexp.MustCompile(("(?im)(" + re + ".*)")))
	}
}

func Sanitize(lines []string, hostnames, queries bool) []string {
	joined := joinQueryLines(lines)
	if queries {
		sanitizeQueries(joined)
	}
	if hostnames {
		sanitizeHostnames(joined)
	}
	return joined
}

func sanitizeHostnames(lines []string) {
	for i := range lines {
		lines[i] = hostnameRE.ReplaceAllStringFunc(lines[i], replaceHostname)
	}
}

func sanitizeQueries(lines []string) {
	for i := range lines {
		for _, re := range queryInLineRe {
			lines[i] = re.ReplaceAllStringFunc(lines[i], queryToFingerprint)
		}
	}
}

func joinQueryLines(lines []string) []string {
	inQuery := false
	joined := []string{}
	queryString := ""

	separator := ""

	for _, line := range lines {
		if !inQuery && mightBeAQueryLine(line) {
			inQuery = true
		}
		if inQuery {
			if strings.HasPrefix(line, "***") {
				joined = append(joined, queryString)
				queryString = ""
				joined = append(joined, line)
				inQuery = false
				separator = ""
				continue
			}
			queryString += separator + line
			separator = "\n"
			if !strings.HasSuffix(strings.TrimSpace(line), ";") {
				continue
			}
			inQuery = false
			separator = ""
			joined = append(joined, queryString)
			queryString = ""
			continue
		}
		joined = append(joined, line)
	}
	return joined
}

func replaceHostname(s string) string {
	if strings.HasSuffix(s, ":") {
		return "<hostname>:"
	}
	return "hostname"
}

func queryToFingerprint(q string) string {
	return query.Fingerprint(q)
}

func mightBeAQueryLine(query string) bool {
	for _, re := range queryLineRe {
		if re.MatchString(query) {
			return true
		}
	}
	return false
}
