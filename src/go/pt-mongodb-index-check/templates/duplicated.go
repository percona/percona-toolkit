// This program is copyright 2022-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

package templates

// {{if $i}},{{end}} adds a comma after the first element.
// When $i == 0 (first element) {{ if $i }} returns false (0)

var Duplicated = `
Duplicated indexes
{{ range . }}
{{ .Namespace }}, index '{{ .Name }}', with fields { {{- range $i, $val := .Key }}{{if $i}}, {{end}}{{ $val.Key }}:{{ $val.Value }}{{ end -}} } is the prefix of '{{ .ContainerName }}' with fields { {{- range $i, $val := .ContainerKey }}{{if $i}}, {{end}}{{ $val.Key }}:{{ $val.Value }}{{ end -}} }{{ end}}
`
