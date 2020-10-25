package templates

var TPL = `{{define "report"}}
{{ template "port_and_datadir" .PortAndDatadir }}
{{ template "tablespaces" .Tablespaces }}
{{ if .SlaveHosts96 -}}
  {{ template "slaves_and_lag" .SlaveHosts96 }}
{{- else if .SlaveHosts10 -}}
  {{ template "slaves_and_lag" .SlaveHosts10 }}
{{- else -}}
  {{ template "slaves_and_log_none" }}
{{- end }}
{{ template "cluster" .ClusterInfo }}
{{ template "databases" .AllDatabases }}
{{ template "index_cache_ratios" .IndexCacheHitRatio }}
{{ template "table_cache_ratios" .TableCacheHitRatio }}
{{ template "global_wait_events" .GlobalWaitEvents }}
{{ template "connected_clients" .ConnectedClients }}
{{ template "counters_header" .Sleep }}
{{ template "counters" .Counters }}
{{ template "table_access" .TableAccess }}
{{ template "settings" .Settings }}
{{ template "processes" .Processes }}
{{ end }} {{/* end "report" */}}` +
	`
{{ define "port_and_datadir" -}}
##### --- Database Port and Data_Directory --- ####
+----------------------+----------------------------------------------------+
|         Name         |                      Setting                       |
+----------------------+----------------------------------------------------+
| {{ printf "%-20s" .Name }} | {{ printf "%-50s" .Setting }} |
+----------------------+----------------------------------------------------+
{{ end -}}
` +
	`{{ define "tablespaces" -}}
##### --- List of Tablespaces ---- ######
+----------------------+----------------------+----------------------------------------------------+
|         Name         |         Owner        |               Location                             |
+----------------------+----------------------+----------------------------------------------------+
{{ range . -}}
| {{ printf "%-20s" .Name }} | {{ printf "%-20s" .Owner }} | {{ printf "%-50s" .Location }} |
{{ end -}}
+----------------------+----------------------+----------------------------------------------------+
{{ end -}} {{/* end define */}}
` +
	`{{ define "slaves_and_lag" -}}
##### --- Slave and the lag with Master --- ####
+----------------------+----------------------+--------------------------------+-------------------+
|  Application Name    |    Client Address    |           State                |      Lag          |
+----------------------+----------------------+--------------------------------+-------------------+
{{ range . -}}` +
	`| {{ convertnullstring .ApplicationName | printf "%-20s" }} | ` +
	`{{ convertnullstring .ClientAddr | printf "%-20s" }} | ` +
	`{{ convertnullstring .State | printf "%-30s" }} | ` +
	`{{ convertnullfloat64 .ByteLag | printf "% 17.2f" }} |` + "\n" +
	`{{ end -}}
+----------------------+----------------------+----------------------------------------------------+
{{ end -}} {{/* end define */}}
` +
	`{{- define "slaves_and_log_none" -}}
##### --- Slave and the lag with Master --- ####
There are no slave hosts
{{ end -}} {{/* end define */}}
` +
	`{{ define "cluster" -}}
##### --- Cluster Information --- ####
{{ if . -}}
+------------------------------------------------------------------------------------------------------+
{{- range . }}
 Usename        : {{ trim 20 .Usename }}
 Time           : {{ printf "%v" .Time }}
 Client Address : {{ convertnullstring .ClientAddr | trim 20 }}
 Client Hostname: {{ convertnullstring .ClientHostname | trim 90 }}
 Version        : {{ trim 90 .Version }}
 Started        : {{ printf "%v" .Started }}
 Is Slave       : {{ .IsSlave }}
+------------------------------------------------------------------------------------------------------+
{{ end -}}
{{ else -}}
There is no Cluster info
{{ end -}}
{{- end -}} {{/* end define */}}
` +
	`{{ define "databases" -}}
##### --- Databases --- ####
+----------------------+------------+
|       Dat Name       |    Size    |
+----------------------+------------+
{{ range . -}}
| {{ printf "%-20s" .Datname }} | {{ printf "%10s" .PgSizePretty }} |
{{ end -}}
+----------------------+------------+
{{ end }} {{/* end define */}}
` +
	`{{ define "index_cache_ratios" -}}
##### --- Index Cache Hit Ratios --- ####
{{ if . -}}
{{ range $dbname, $value := . }}
Database: {{ $dbname }}
+----------------------+------------+
|      Index Name      |    Ratio   |
+----------------------+------------+
| {{ printf "%-20s" .Name }} |     {{ convertnullfloat64 .Ratio | printf "% 5.2f" }}  |
+----------------------+------------+
{{ else -}}
  No stats available
{{ end -}}
{{ end -}}
{{ end -}} {{/* end define */}}
` +
	`{{ define "table_cache_ratios" -}}
##### --- Table Cache Hit Ratios --- ####
{{ if . -}}
{{ range $dbname, $value := . -}}
Database: {{ $dbname }}
+----------------------+------------+
|      Index Name      |    Ratio   |
+----------------------+------------+
| {{ printf "%-20s" .Name }} |      {{ printf "%5.2f" .Ratio.Float64 }} |
+----------------------+------------+
{{ else -}}
  No stats available
{{ end -}}
{{ end }}
{{- end -}} {{/* end define */}}
` +
	`{{ define "global_wait_events" -}}
##### --- List of Wait_events for the entire Cluster - all-databases --- ####
{{ if . -}}
+----------------------+----------------------+---------+
|   Wait Event Type    |        Event         |  Count  |
+----------------------+----------------------+---------+
{{ range . -}}
| {{ printf "%-20s" .WaitEventType }} | {{ printf "%-20s" .WaitEvent }} | {{ printf "% 5d" .Count }}   |
{{ end -}}
+----------------------+----------------------+---------+
{{ else -}}
  No stats available
{{ end -}}
{{- end -}} {{/* end define */}}
` +
	`{{ define "connected_clients" -}}
##### --- List of users and client_addr or client_hostname connected to --all-databases --- ####
{{ if . -}}
+----------------------+------------+---------+----------------------+---------+
|   Wait Event Type    |        Client        |         State        |  Count  |
+----------------------+------------+---------+----------------------+---------+
{{ range . -}}` +
	`| {{ printf "%-20s" .Usename }} | ` +
	`{{ convertnullstring .Client | printf "%-20s" }} | ` +
	`{{ convertnullstring .State | printf "%-20s" }} | ` +
	`{{ convertnullint64 .Count | printf "% 7d" }} |` + "\n" +
	`{{ end -}}
+----------------------+------------+---------+----------------------+---------+
{{ else -}}
  No stats available
{{ end -}}
{{- end -}} {{/* end define */}}
` +

	/*
	   Counters header
	*/
	`{{ define "counters_header" -}}` +
	"##### --- Counters diff after {{ . }} seconds --- ####\n" +
	`{{end}}` +

	/*
	   Counters
	*/
	`{{ define "counters" -}}` +
	"+----------------------" +
	"+-------------" +
	"+------------" +
	"+--------------" +
	"+-------------" +
	"+------------" +
	"+-------------" +
	"+------------" +
	"+-------------" +
	"+------------" +
	"+------------" +
	"+-----------" +
	"+-----------" +
	"+-----------" +
	"+------------+" + "\n" +
	"| Database             " +
	"| Numbackends " +
	"| XactCommit " +
	"| XactRollback " +
	"| BlksRead    " +
	"| BlksHit    " +
	"| TupReturned " +
	"| TupFetched " +
	"| TupInserted " +
	"| TupUpdated " +
	"| TupDeleted " +
	"| Conflicts " +
	"| TempFiles " +
	"| TempBytes " +
	"| Deadlocks  |" + "\n" +
	"+----------------------" +
	"+-------------" +
	"+------------" +
	"+--------------" +
	"+-------------" +
	"+------------" +
	"+-------------" +
	"+------------" +
	"+-------------" +
	"+------------" +
	"+------------" +
	"+-----------" +
	"+-----------" +
	"+-----------" +
	"+------------+" + "\n" +
	`{{ range $key, $value := . -}} ` +
	`| {{ printf "%-20s" (index $value 2).Datname }} ` +
	`| {{ printf "% 7d"  (index $value 2).Numbackends }}     ` +
	`| {{ printf "% 7d"  (index $value 2).XactCommit }}    ` +
	`| {{ printf "% 7d"  (index $value 2).XactRollback }}      ` +
	`| {{ printf "% 7d"  (index $value 2).BlksRead }}     ` +
	`| {{ printf "% 7d"  (index $value 2).BlksHit }}    ` +
	`| {{ printf "% 7d"  (index $value 2).TupReturned }}     ` +
	`| {{ printf "% 7d"  (index $value 2).TupFetched }}    ` +
	`| {{ printf "% 7d"  (index $value 2).TupInserted }}     ` +
	`| {{ printf "% 7d"  (index $value 2).TupUpdated }}    ` +
	`| {{ printf "% 7d"  (index $value 2).TupDeleted }}    ` +
	`| {{ printf "% 7d"  (index $value 2).Conflicts }}   ` +
	`| {{ printf "% 7d"  (index $value 2).TempFiles }}   ` +
	`| {{ printf "% 7d"  (index $value 2).TempBytes }}   ` +
	`| {{ printf "% 7d"  (index $value 2).Deadlocks }}    ` +
	"|\n" +
	`{{ end }}` +
	"+----------------------" +
	"+-------------" +
	"+------------" +
	"+--------------" +
	"+-------------" +
	"+------------" +
	"+-------------" +
	"+------------" +
	"+-------------" +
	"+------------" +
	"+------------" +
	"+-----------" +
	"+-----------" +
	"+-----------" +
	"+------------+" + "\n" +
	`{{ end }}` +

	`{{ define "table_access" -}}` +

	"##### --- Table access per database --- ####\n" +
	`{{ range $dbname, $values := . -}}` +
	"Database: {{ $dbname }}\n" +
	"+----------------------------------------------------" +
	"+------" +
	"+--------------------------------" +
	"+---------+\n" +
	"|                       Relname                      " +
	"| Kind " +
	"|             Datname            " +
	"|  Count  |\n" +
	"+----------------------------------------------------" +
	"+------" +
	"+--------------------------------" +
	"+---------+\n" +
	`{{ range . -}}
| {{ printf "%-50s" .Relname }} ` +
	`|   {{ printf "%1s" .Relkind }}  ` +
	`| {{ convertnullstring .Datname | printf "%-30s" }} ` +
	`| {{ convertnullint64 .Count | printf "% 7d" }} ` +
	"|\n" +
	"{{ end }}" +
	"+----------------------------------------------------" +
	"+------" +
	"+--------------------------------" +
	"+---------+\n" +
	"{{ end -}}" +
	"{{ end }}" +

	`{{ define "settings" -}}` +
	/*
	   Settings
	*/
	"##### --- Instance settings --- ####\n" +
	"                      Setting                 " +
	"                           Value                     \n" +
	`{{ range $name, $values := . -}}` +
	` {{ printf "%-45s" .Name }} ` +
	`: {{ printf "%s" .Setting }}` +
	"\n" +
	"{{ end }}" +
	"{{ end }}" +
	/*
	   Processes
	*/
	`{{ define "processes" -}}` +
	"##### --- Processes start up command --- ####\n" +
	"{{ if . -}}" +
	"  PID  " +
	":    Command line\n" +
	`{{ range $name, $values := . }}` +
	` {{ printf "% 5d" .PID }} ` +
	`: {{ printf "%-s" .CmdLine }}  ` +
	"\n" +
	"{{ end }}" +
	"{{ else }}" +
	"No postgres process found\n" +
	"{{ end }}" +
	"{{ end }}"
