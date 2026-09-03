// This program is copyright 2016-2026 Percona LLC and/or its affiliates.
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

const WiredTiger = `
{{ if . -}}
# WiredTiger ##########################################################################################
          Cache Used | {{printf "%.2f" .CacheUsedMB}} MB / {{printf "%.2f" .CacheMaxMB}} MB ({{printf "%.1f" .CacheUsedPct}}%)
         Dirty Pages | {{printf "%.2f" .DirtyMB}} MB ({{printf "%.1f" .DirtyPct}}%)
  Evicted Unmodified | {{.PagesEvictedUnmodified}}
    Evicted Modified | {{.PagesEvictedModified}}
    Read Into Cache  | {{.PagesReadIntoCache}}
   Written Fr Cache  | {{.PagesWrittenFromCache}}
{{- if .TcmallocAvailable }}
# TCMalloc ############################################################################################
       Heap Size     | {{printf "%.2f" .TcmallocHeapMB}} MB
   Allocated (RSS)   | {{printf "%.2f" .TcmallocAllocMB}} MB
   Pageheap Free     | {{printf "%.2f" .TcmallocPageheapFreeMB}} MB
 Pageheap Unmapped   | {{printf "%.2f" .TcmallocPageheapUnmappedMB}} MB
  Thread Cache Free  | {{printf "%.2f" .TcmallocThreadCacheFreeMB}} MB
{{- end }}
{{- end }}
`
