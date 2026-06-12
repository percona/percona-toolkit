-- See https://www.percona.com/doc/percona-server/LATEST/diagnostics/response_time_distribution.html

-- This plugin is used for gathering statistics.
UNINSTALL PLUGIN QUERY_RESPONSE_TIME_AUDIT;

-- This plugin provides the interface (QUERY_RESPONSE_TIME) to output gathered statistics.
UNINSTALL PLUGIN QUERY_RESPONSE_TIME;

-- This plugin provides the interface (QUERY_RESPONSE_TIME_READ) to output gathered statistics.
UNINSTALL PLUGIN QUERY_RESPONSE_TIME_READ;

-- This plugin provides the interface (QUERY_RESPONSE_TIME_WRITE) to output gathered statistics.
UNINSTALL PLUGIN QUERY_RESPONSE_TIME_WRITE;
