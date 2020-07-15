#!/bin/bash
USERNAME=postgres
PASSWORD=root
PORT9=6432
PORT10=6433
PORT12=6435
DO_CLEANUP=0

if [ ! "$(docker ps -q -f name=go_postgres9_1)" ]; then
    DO_CLEANUP=1
    docker-compose up -d --force-recreate
    sleep 20
fi

xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-trim  \
    --query-interpolate \
    --query-type AllDatabases \
    --package models \
    --out ./ << ENDSQL
SELECT datname 
  FROM pg_database 
 WHERE datistemplate = false
ENDSQL

xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-trim \
    --query-interpolate \
    --query-only-one \
    --query-type PortAndDatadir \
    --package models \
    --out ./ << ENDSQL
SELECT name, 
       setting 
  FROM pg_settings 
 WHERE name IN ('port','data_directory')
ENDSQL

COMMENT="Tablespaces"
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-trim  \
    --query-interpolate \
    --query-type Tablespaces \
    --query-type-comment "$COMMENT" \
    --package models \
    --out ./ << ENDSQL
  SELECT spcname AS Name,
         pg_catalog.pg_get_userbyid(spcowner) AS Owner,
         pg_catalog.pg_tablespace_location(oid) AS Location 
  FROM pg_catalog.pg_tablespace
ORDER BY 1
ENDSQL

FIELDS='Usename string,Time time.Time,ClientAddr sql.NullString,ClientHostname sql.NullString,Version string,Started time.Time,IsSlave bool'
COMMENT='Cluster info'
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-trim  \
    -k smart \
    --query-type ClusterInfo \
    --query-fields "$FIELDS" \
    --query-interpolate \
    --query-type-comment "$COMMENT" \
    --query-allow-nulls \
    --package models \
    --out ./ << ENDSQL
SELECT usename, now() AS "Time", 
       client_addr,
       client_hostname, 
       version() AS version, 
       pg_postmaster_start_time() AS Started, 
       pg_is_in_recovery() AS "Is_Slave" 
  FROM pg_stat_activity 
 WHERE pid = pg_backend_pid()
ENDSQL

COMMENT="Databases"
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT12}/?sslmode=disable \
    --query-mode \
    --query-trim  \
    --query-interpolate \
    --query-type-comment "$COMMENT" \
    --query-type Databases \
    --package models \
    --out ./ << ENDSQL
SELECT datname, pg_size_pretty(pg_database_size(datname)) 
  FROM pg_stat_database
  WHERE datid <> 0
ENDSQL
 
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-trim  \
    --query-interpolate \
    --query-type Connections \
    --package models \
    --out ./ << ENDSQL
  SELECT state, count(*) 
    FROM pg_stat_activity 
GROUP BY 1
ENDSQL
 
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT12}/?sslmode=disable \
    --query-mode \
    --query-interpolate \
    --query-trim  \
    --query-type Counters \
    --package models \
    --out ./ << ENDSQL
  SELECT COALESCE(datname, '') datname, numbackends, xact_commit, xact_rollback,
         blks_read, blks_hit, tup_returned, tup_fetched, tup_inserted, 
         tup_updated, tup_deleted, conflicts, temp_files, 
         temp_bytes, deadlocks 
    FROM pg_stat_database
ORDER BY datname
ENDSQL

FIELDS='Relname string, Relkind string, Datname sql.NullString, Count sql.NullInt64'
COMMENT='Table Access'
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT12}/?sslmode=disable \
    --query-mode \
    --query-trim  \
    --query-type TableAccess \
    --query-fields "$FIELDS" \
    --query-type-comment "$COMMENT" \
    --query-interpolate \
    --query-allow-nulls \
    --package models \
    --out ./ << ENDSQL 
  SELECT c.relname, c.relkind, b.datname datname, count(*) FROM pg_locks a
    JOIN pg_stat_database b 
      ON a.database=b.datid 
    JOIN pg_class c 
      ON a.relation=c.oid 
   WHERE a.relation IS NOT NULL 
     AND a.database IS NOT NULL 
GROUP BY 1,2,3
ENDSQL

FIELDS='Name string,Ratio sql.NullFloat64'
COMMENT='Table cache hit ratio'
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable --query-mode --query-trim  \
    --query-type TableCacheHitRatio \
    --query-fields "$FIELDS" \
    --query-interpolate \
    --query-only-one \
    --query-type-comment "$COMMENT" \
    --package models \
    --out ./ << ENDSQL
SELECT 'cache hit rate' AS name,
       CASE WHEN (sum(heap_blks_read) + sum(idx_blks_hit)) > 0
       THEN
         sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read))
       ELSE 0
       END  AS ratio
  FROM pg_statio_user_tables
ENDSQL

FIELDS='Name string,Ratio sql.NullFloat64'
COMMENT='Table cache hit ratio'
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-fields "$FIELDS" \
    --query-trim  \
    --query-allow-nulls \
    --query-only-one \
    --query-type IndexCacheHitRatio \
    --query-type-comment "$COMMENT" \
    --package models \
    --out ./ << ENDSQL
SELECT 'index hit rate' AS name, 
       CASE WHEN sum(idx_blks_hit) IS NULL 
         THEN 0 
         ELSE (sum(idx_blks_hit)) / sum(idx_blks_hit + idx_blks_read) 
       END AS ratio 
  FROM pg_statio_user_indexes 
 WHERE (idx_blks_hit + idx_blks_read) > 0
ENDSQL

xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-trim  \
    --query-type GlobalWaitEvents \
    --package models \
    --out ./ << ENDSQL
  SELECT wait_event_type, wait_event, count(*) 
    FROM pg_stat_activity 
   WHERE wait_event_type IS NOT NULL 
      OR wait_event IS NOT NULL 
GROUP BY 1,2
ENDSQL

xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-trim  \
    --query-interpolate \
    --query-allow-nulls \
    --query-type DatabaseWaitEvents \
    --package models \
    --out ./ << ENDSQL
  SELECT c.relname, c.relkind, d.wait_event_type, d.wait_event, b.datname, count(*) 
    FROM pg_locks a 
    JOIN pg_stat_database b ON a.database=b.datid 
    JOIN pg_class c ON a.relation=c.oid 
    JOIN pg_stat_activity d ON a.pid = d.pid 
   WHERE a.relation IS NOT NULL 
     AND a.database IS NOT NULL 
     AND (d.wait_event_type IS NOT NULL OR d.wait_event IS NOT NULL) 
GROUP BY 1,2,3,4,5
ENDSQL

COMMENT="Connected clients list"
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-trim \
    --query-type ConnectedClients \
    --query-type-comment "$COMMENT" \
    --query-allow-nulls \
    --query-interpolate \
    --package models \
    --out ./ << ENDSQL
  SELECT usename, 
         CASE WHEN client_hostname IS NULL THEN client_addr::text ELSE client_hostname END AS client, 
         state, count(*) 
    FROM pg_stat_activity 
   WHERE state IS NOT NULL 
GROUP BY 1,2,3 
ORDER BY 4 desc,3
ENDSQL

# Postgre 9
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-trim  \
    --query-type SlaveHosts96 \
    --query-interpolate \
    --query-allow-nulls \
    --package models \
    --out ./ << ENDSQL
SELECT application_name, client_addr, state, sent_offset - (replay_offset - (sent_xlog - replay_xlog) * 255 * 16 ^ 6 ) AS byte_lag 
    FROM ( SELECT application_name, client_addr, client_hostname, state, 
    ('x' || lpad(split_part(sent_location::TEXT,   '/', 1), 8, '0'))::bit(32)::bigint AS sent_xlog, 
    ('x' || lpad(split_part(replay_location::TEXT, '/', 1), 8, '0'))::bit(32)::bigint AS replay_xlog, 
    ('x' || lpad(split_part(sent_location::TEXT,   '/', 2), 8, '0'))::bit(32)::bigint AS sent_offset, 
    ('x' || lpad(split_part(replay_location::TEXT, '/', 2), 8, '0'))::bit(32)::bigint AS replay_offset 
    FROM pg_stat_replication ) AS s
ENDSQL

# Postgre 10
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT10}/?sslmode=disable \
    --query-mode \
    --query-trim \
    --query-interpolate \
    --query-allow-nulls \
    --query-type SlaveHosts10 \
    --package models \
    --out ./ << ENDSQL
SELECT application_name, client_addr, state, sent_offset - (replay_offset - (sent_lsn - replay_lsn) * 255 * 16 ^ 6 ) AS byte_lag 
    FROM ( SELECT application_name, client_addr, client_hostname, state, 
    ('x' || lpad(split_part(sent_lsn::TEXT,   '/', 1), 8, '0'))::bit(32)::bigint AS sent_lsn, 
    ('x' || lpad(split_part(replay_lsn::TEXT, '/', 1), 8, '0'))::bit(32)::bigint AS replay_lsn, 
    ('x' || lpad(split_part(sent_lsn::TEXT,   '/', 2), 8, '0'))::bit(32)::bigint AS sent_offset, 
    ('x' || lpad(split_part(replay_lsn::TEXT, '/', 2), 8, '0'))::bit(32)::bigint AS replay_offset 
    FROM pg_stat_replication ) AS s
ENDSQL


xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT10}/?sslmode=disable \
    --query-mode \
    --query-trim \
    --query-only-one \
    --query-type ServerVersion \
    --package models \
    --out ./ << ENDSQL
SELECT current_setting('server_version_num') AS version
ENDSQL

FIELDS='Name string,Setting string'
COMMENT='Settings'
xo pgsql://${USERNAME}:${PASSWORD}@127.0.0.1:${PORT9}/?sslmode=disable \
    --query-mode \
    --query-fields "$FIELDS" \
    --query-trim  \
    --query-allow-nulls \
    --query-type Setting \
    --query-type-comment "$COMMENT" \
    --package models \
    --out ./ << ENDSQL
SELECT name, setting 
  FROM pg_settings
ENDSQL

if [ $DO_CLEANUP == 1 ]; then 
    docker-compose down --volumes
fi
