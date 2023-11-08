-- See https://www.percona.com/doc/percona-server/LATEST/diagnostics/response_time_distribution.html

-- This plugin is used for gathering statistics.
INSTALL PLUGIN QUERY_RESPONSE_TIME_AUDIT SONAME 'query_response_time.so';

-- This plugin provides the interface (QUERY_RESPONSE_TIME) to output gathered statistics.
INSTALL PLUGIN QUERY_RESPONSE_TIME SONAME 'query_response_time.so';

-- This plugin provides the interface (QUERY_RESPONSE_TIME_READ) to output gathered statistics.
INSTALL PLUGIN QUERY_RESPONSE_TIME_READ SONAME 'query_response_time.so';

-- This plugin provides the interface (QUERY_RESPONSE_TIME_WRITE) to output gathered statistics.
INSTALL PLUGIN QUERY_RESPONSE_TIME_WRITE SONAME 'query_response_time.so';

-- Start collecting query time metrics,
SET GLOBAL query_response_time_stats = on;
