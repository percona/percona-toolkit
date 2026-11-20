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
{{ header "WiredTiger" }}
           Storage Engine | {{ .Engine }}
               Cache Size | {{ bytes .CacheMaxBytes }}
               Cache Used | {{ bytes .CacheUsedBytes }} ({{ pct .CacheUsedPct }})
               Cache Free | {{ bytes .CacheFreeBytes }} ({{ pct .CacheFreePct }})
              Cache Dirty | {{ bytes .CacheDirtyBytes }} ({{ pct .CacheDirtyPct }})
{{- with .CacheUpdatesBytes }}
            Cache Updates | {{ bytes . }} ({{ pct $.CacheUpdatesPct }})
{{- end }}
{{- if .Window }}
              Rate Window | {{ dur .Window }}
          Read Into Cache | {{ rate .PagesReadIntoCache.PerSec }} pages/s, {{ bytes .BytesReadIntoCache.PerSecBytes }}/s uncompressed
       Written From Cache | {{ rate .PagesWrittenFromCache.PerSec }} pages/s, {{ bytes .BytesWrittenFromCache.PerSecBytes }}/s uncompressed
 Unmodified Pages Evicted | {{ rate .UnmodifiedPagesEvicted.PerSec }}/s
   Modified Pages Evicted | {{ rate .ModifiedPagesEvicted.PerSec }}/s
App Thread Evict Attempts | {{ rate .AppThreadEvictions.PerSec }}/s
 App Thread Wait on Cache | {{ rate .AppThreadCacheWaitUsecs.PerSecMillis }} ms/s
{{- end }}
`
