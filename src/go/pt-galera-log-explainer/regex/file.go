package regex

import "regexp"

var RegexOperatorFileType = regexp.MustCompile(`\"file\":\"/([a-z]+/)+(?P<filetype>[a-z._-]+.log)\"}$`)
var RegexOperatorShellDebugFileType = regexp.MustCompile(`^\+`)

func FileType(line string, operator bool) string {
	if !operator {
		// if not operator, we can't really guess
		return "error.log"
	}
	r, err := internalRegexSubmatch(RegexOperatorFileType, line)
	if err != nil {
		if RegexOperatorShellDebugFileType.MatchString(line) {
			return "operator shell"
		}
		return ""
	}
	t := r[RegexOperatorFileType.SubexpIndex("filetype")]
	switch t {
	case "mysqld.post.processing.log":
		return "post.processing.log"
	case "wsrep_recovery_verbose.log":
		return "recovery.log"
	case "mysqld-error.log":
		return "error.log"
	case "innobackup.backup.log":
		return "backup.log"
	default:
		return t
	}
}
