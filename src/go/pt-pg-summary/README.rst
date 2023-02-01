pt-pg-summary
=============
**pt-pg-summary** collects information about a PostgreSQL cluster.

Usage
-----

``pt-pg-summary [options] [host:[port]]``

Binaries
--------
Please check the `releases <https://github.com/percona/toolkit-go/releases>`_ tab to download the binaries.

Parameters
^^^^^^^^^^

+--------+---------------------------------+---------+----------------------------------------------------------------------------+
| Short  | Long                            | Default | Description                                                                |
+========+=================================+=========+============================================================================+
|        | ``--help``                      |         | Show context-sensitive help (also try ``--help-long`` and ``--help-man``). |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+
|        | ``--version``                   |         | Show application version.                                                  |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+
|        | ``--databases=DATABASES``       |         | Summarize this comma-separated list of databases. All if not specified.    |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+
| ``-h`` | ``--host=HOST``                 |         | Host to connect to.                                                        |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+
| ``-W`` | ``--password=PASSWORD``         |         | Password to use when connecting.                                           |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+
| ``-p`` | ``--port=PORT``                 |         | Port number to use for connection.                                         |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+
|        | ``--sleep=SLEEP``               | 10      | Seconds to sleep when gathering status counters.                           |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+
| ``-U`` | ``--username=USERNAME``         |         | User for login if not current user.                                        |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+
|        | ``--disable-ssl``               | true    | Disable SSL for the connection.                                            |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+
|        | ``--verbose``                   | false   | Show verbose log.                                                          |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+
|        | ``--debug``                     | false   | Show debug information in the logs.                                        |
+--------+---------------------------------+---------+----------------------------------------------------------------------------+


.. Currently hidden
..       --list-encrypted-tables              Include a list of the encrypted tables in all databases
..       --ask-pass                           Prompt for a password when connecting to PostgreSQL
..       --config                             Config file
..       --defaults-file                      Only read PostgreSQL options from the given file
..       --read-samples                       Create a report from the files found in this directory
..       --save-samples                       Save the data files used to generate the summary in this directory


Output
^^^^^^

The output is grouped into these categories:

AllDatabases
    Selects ``datname`` from ``pg_database`` where ``datistemplate`` is false.

ClusterInfo
    Selects cluster information from ``pg_stat_activity``.

ConnectedClients
    Counts the connected clients by selecting from ``pg_stat_activity``.

Connections
    Selects ``state`` from ``pg_stat_activity`` and counts them.

Counters
    Selects various counter values from ``pg_stat_database``.

DatabaseWaitEvents
    Shows database wait events from ``pg_locks``, ``pg_stat_database``, ``pg_class``, and ``pg_stat_activity``.

Databases
    Shows the name and size of databases from ``pg_stat_database``.

GlobalWaitEvents
    Shows global wait evens from ``pg_stat_activity``.

IndexCacheHitRatio
    Shows index hit ratios from ``pg_statio_user_indexes``.

PortAndDatadir
    Shows port and data directory name from ``pg_settings``.

ServerVersion
    Shows the value of ``server_version_num``.

Setting
    Selects ``name`` and ``setting`` from ``pg_settings``.

SlaveHosts10
    Selects information for PostgreSQL version 10.

SlaveHosts96
    Selects information for PostgreSQL version 9.6.

TableAccess
    Shows table access information by selecting from ``pg_locks``, ``pg_stat_database`` and ``pg_class``.

TableCacheHitRatio
    Shows table cache hit ratio information from ``pg_statio_user_tables``.

Tablespaces
    Show owner and location from ``pg_catalog.pg_tablespace``.


Output example
""""""""""""""

.. code-block:: html

    ##### --- Database Port and Data_Directory --- ####
    +----------------------+----------------------------------------------------+
    |         Name         |                      Setting                       |
    +----------------------+----------------------------------------------------+
    | data_directory       | /var/lib/postgresql/data                           |
    +----------------------+----------------------------------------------------+

    ##### --- List of Tablespaces ---- ######
    +----------------------+----------------------+----------------------------------------------------+
    |         Name         |         Owner        |               Location                             |
    +----------------------+----------------------+----------------------------------------------------+
    | pg_default           | postgres             |                                                    |
    | pg_global            | postgres             |                                                    |
    +----------------------+----------------------+----------------------------------------------------+


    ##### --- Cluster Information --- ####
    +------------------------------------------------------------------------------------------------------+
     Usename        : postgres
     Time           : 2020-04-21 13:38:22.770077 +0000 UTC
     Client Address : 172.19.0.1
     Client Hostname:
     Version        : PostgreSQL 9.6.17 on x86_64-pc-linux-gnu (Debian 9.6.17-2.pgdg90+1), compiled by
     Started        : 2020-04-21 13:36:59.909175 +0000 UTC
     Is Slave       : false
    +------------------------------------------------------------------------------------------------------+

    ##### --- Databases --- ####
    +----------------------+------------+
    |       Dat Name       |    Size    |
    +----------------------+------------+
    | postgres             |    7071 kB |
    | template1            |    6961 kB |
    | template0            |    6961 kB |
    +----------------------+------------+

    ##### --- Index Cache Hit Ratios --- ####

    Database: postgres
    +----------------------+------------+
    |      Index Name      |    Ratio   |
    +----------------------+------------+
    | index hit rate       |      0.00  |
    +----------------------+------------+

    ##### --- Table Cache Hit Ratios --- ####
    Database: postgres
    +----------------------+------------+
    |      Index Name      |    Ratio   |
    +----------------------+------------+
    | cache hit rate       |       0.00 |
    +----------------------+------------+

    ##### --- List of Wait_events for the entire Cluster - all-databases --- ####
    No stats available

    ##### --- List of users and client_addr or client_hostname connected to --all-databases --- ####
    +----------------------+------------+---------+----------------------+---------+
    |   Wait Event Type    |        Client        |         State        |  Count  |
    +----------------------+------------+---------+----------------------+---------+
    | postgres             | 172.19.0.1/32        | active               |       1 |
    +----------------------+------------+---------+----------------------+---------+

    ##### --- Counters diff after 10 seconds --- ####

    +----------------------+-------------+------------+--------------+-------------+------------+-------------+------------+-------------+------------+------------+-----------+-----------+-----------+------------+
    | Database             | Numbackends | XactCommit | XactRollback | BlksRead    | BlksHit    | TupReturned | TupFetched | TupInserted | TupUpdated | TupDeleted | Conflicts | TempFiles | TempBytes | Deadlocks  |
    +----------------------+-------------+------------+--------------+-------------+------------+-------------+------------+-------------+------------+------------+-----------+-----------+-----------+------------+
    | postgres             |       0     |       0    |       0      |       0     |       0    |       0     |       0    |       0     |       0    |       0    |       0   |       0   |       0   |       0    |
    | template0            |       0     |       0    |       0      |       0     |       0    |       0     |       0    |       0     |       0    |       0    |       0   |       0   |       0   |       0    |
    | template1            |       0     |       0    |       0      |       0     |       0    |       0     |       0    |       0     |       0    |       0    |       0   |       0   |       0   |       0    |
    +----------------------+-------------+------------+--------------+-------------+------------+-------------+------------+-------------+------------+------------+-----------+-----------+-----------+------------+

    ##### --- Table access per database --- ####
    Database: postgres
    +----------------------------------------------------+------+--------------------------------+---------+
    |                       Relname                      | Kind |             Datname            |  Count  |
    +----------------------------------------------------+------+--------------------------------+---------+
    | pg_class                                           |   r  | postgres                       |       1 |
    | pg_stat_database                                   |   v  | postgres                       |       1 |
    | pg_locks                                           |   v  | postgres                       |       1 |
    | pg_class_tblspc_relfilenode_index                  |   i  | postgres                       |       1 |
    | pg_class_relname_nsp_index                         |   i  | postgres                       |       1 |
    | pg_class_oid_index                                 |   i  | postgres                       |       1 |
    +----------------------------------------------------+------+--------------------------------+---------+

    ##### --- Instance settings --- ####
                          Setting                                            Value
    allow_system_table_mods                       : off
    application_name                              :
    archive_command                               : (disabled)
    archive_mode                                  : off
    archive_timeout                               : 0
    array_nulls                                   : on
    authentication_timeout                        : 60
    autovacuum                                    : on
    autovacuum_analyze_scale_factor               : 0.1
    autovacuum_analyze_threshold                  : 50
    autovacuum_freeze_max_age                     : 200000000
    autovacuum_max_workers                        : 3
    autovacuum_multixact_freeze_max_age           : 400000000
    autovacuum_naptime                            : 60
    autovacuum_vacuum_cost_delay                  : 20
    autovacuum_vacuum_cost_limit                  : -1
    autovacuum_vacuum_scale_factor                : 0.2
    autovacuum_vacuum_threshold                   : 50
    autovacuum_work_mem                           : -1
    backend_flush_after                           : 0
    backslash_quote                               : safe_encoding
    bgwriter_delay                                : 200
    bgwriter_flush_after                          : 64
    bgwriter_lru_maxpages                         : 100
    bgwriter_lru_multiplier                       : 2
    block_size                                    : 8192
    bonjour                                       : off
    bonjour_name                                  :
    bytea_output                                  : hex
    check_function_bodies                         : on
    checkpoint_completion_target                  : 0.5
    checkpoint_flush_after                        : 32
    checkpoint_timeout                            : 300
    checkpoint_warning                            : 30
    client_encoding                               : UTF8
    client_min_messages                           : notice
    cluster_name                                  :
    commit_delay                                  : 0
    commit_siblings                               : 5
    config_file                                   : /var/lib/postgresql/data/postgresql.conf
    constraint_exclusion                          : partition
    cpu_index_tuple_cost                          : 0.005
    cpu_operator_cost                             : 0.0025
    cpu_tuple_cost                                : 0.01
    cursor_tuple_fraction                         : 0.1
    data_checksums                                : off
    data_directory                                : /var/lib/postgresql/data
    data_sync_retry                               : off
    DateStyle                                     : ISO, MDY
    db_user_namespace                             : off
    deadlock_timeout                              : 1000
    debug_assertions                              : off
    debug_pretty_print                            : on
    debug_print_parse                             : off
    debug_print_plan                              : off
    debug_print_rewritten                         : off
    default_statistics_target                     : 100
    default_tablespace                            :
    default_text_search_config                    : pg_catalog.english
    default_transaction_deferrable                : off
    default_transaction_isolation                 : read committed
    default_transaction_read_only                 : off
    default_with_oids                             : off
    dynamic_library_path                          : $libdir
    dynamic_shared_memory_type                    : posix
    effective_cache_size                          : 524288
    effective_io_concurrency                      : 1
    enable_bitmapscan                             : on
    enable_hashagg                                : on
    enable_hashjoin                               : on
    enable_indexonlyscan                          : on
    enable_indexscan                              : on
    enable_material                               : on
    enable_mergejoin                              : on
    enable_nestloop                               : on
    enable_seqscan                                : on
    enable_sort                                   : on
    enable_tidscan                                : on
    escape_string_warning                         : on
    event_source                                  : PostgreSQL
    exit_on_error                                 : off
    external_pid_file                             :
    extra_float_digits                            : 2
    force_parallel_mode                           : off
    from_collapse_limit                           : 8
    fsync                                         : on
    full_page_writes                              : on
    geqo                                          : on
    geqo_effort                                   : 5
    geqo_generations                              : 0
    geqo_pool_size                                : 0
    geqo_seed                                     : 0
    geqo_selection_bias                           : 2
    geqo_threshold                                : 12
    gin_fuzzy_search_limit                        : 0
    gin_pending_list_limit                        : 4096
    hba_file                                      : /var/lib/postgresql/data/pg_hba.conf
    hot_standby                                   : off
    hot_standby_feedback                          : off
    huge_pages                                    : try
    ident_file                                    : /var/lib/postgresql/data/pg_ident.conf
    idle_in_transaction_session_timeout           : 0
    ignore_checksum_failure                       : off
    ignore_system_indexes                         : off
    integer_datetimes                             : on
    IntervalStyle                                 : postgres
    join_collapse_limit                           : 8
    krb_caseins_users                             : off
    krb_server_keyfile                            : FILE:/etc/postgresql-common/krb5.keytab
    lc_collate                                    : en_US.utf8
    lc_ctype                                      : en_US.utf8
    lc_messages                                   : en_US.utf8
    lc_monetary                                   : en_US.utf8
    lc_numeric                                    : en_US.utf8
    lc_time                                       : en_US.utf8
    listen_addresses                              : *
    lo_compat_privileges                          : off
    local_preload_libraries                       :
    lock_timeout                                  : 0
    log_autovacuum_min_duration                   : -1
    log_checkpoints                               : off
    log_connections                               : off
    log_destination                               : stderr
    log_directory                                 : pg_log
    log_disconnections                            : off
    log_duration                                  : off
    log_error_verbosity                           : default
    log_executor_stats                            : off
    log_file_mode                                 : 0600
    log_filename                                  : postgresql-%Y-%m-%d_%H%M%S.log
    log_hostname                                  : off
    log_line_prefix                               :
    log_lock_waits                                : off
    log_min_duration_statement                    : -1
    log_min_error_statement                       : error
    log_min_messages                              : warning
    log_parser_stats                              : off
    log_planner_stats                             : off
    log_replication_commands                      : off
    log_rotation_age                              : 1440
    log_rotation_size                             : 10240
    log_statement                                 : none
    log_statement_stats                           : off
    log_temp_files                                : -1
    log_timezone                                  : Etc/UTC
    log_truncate_on_rotation                      : off
    logging_collector                             : off
    maintenance_work_mem                          : 65536
    max_connections                               : 100
    max_files_per_process                         : 1000
    max_function_args                             : 100
    max_identifier_length                         : 63
    max_index_keys                                : 32
    max_locks_per_transaction                     : 64
    max_parallel_workers_per_gather               : 0
    max_pred_locks_per_transaction                : 64
    max_prepared_transactions                     : 0
    max_replication_slots                         : 0
    max_stack_depth                               : 2048
    max_standby_archive_delay                     : 30000
    max_standby_streaming_delay                   : 30000
    max_wal_senders                               : 0
    max_wal_size                                  : 64
    max_worker_processes                          : 8
    min_parallel_relation_size                    : 1024
    min_wal_size                                  : 5
    old_snapshot_threshold                        : -1
    operator_precedence_warning                   : off
    parallel_setup_cost                           : 1000
    parallel_tuple_cost                           : 0.1
    password_encryption                           : on
    port                                          : 5432
    post_auth_delay                               : 0
    pre_auth_delay                                : 0
    quote_all_identifiers                         : off
    random_page_cost                              : 4
    replacement_sort_tuples                       : 150000
    restart_after_crash                           : on
    row_security                                  : on
    search_path                                   : "$user", public
    segment_size                                  : 131072
    seq_page_cost                                 : 1
    server_encoding                               : UTF8
    server_version                                : 9.6.17
    server_version_num                            : 90617
    session_preload_libraries                     :
    session_replication_role                      : origin
    shared_buffers                                : 16384
    shared_preload_libraries                      :
    sql_inheritance                               : on
    ssl                                           : off
    ssl_ca_file                                   :
    ssl_cert_file                                 : server.crt
    ssl_ciphers                                   : HIGH:MEDIUM:+3DES:!aNULL
    ssl_crl_file                                  :
    ssl_ecdh_curve                                : prime256v1
    ssl_key_file                                  : server.key
    ssl_prefer_server_ciphers                     : on
    standard_conforming_strings                   : on
    statement_timeout                             : 0
    stats_temp_directory                          : pg_stat_tmp
    superuser_reserved_connections                : 3
    synchronize_seqscans                          : on
    synchronous_commit                            : on
    synchronous_standby_names                     :
    syslog_facility                               : local0
    syslog_ident                                  : postgres
    syslog_sequence_numbers                       : on
    syslog_split_messages                         : on
    tcp_keepalives_count                          : 9
    tcp_keepalives_idle                           : 7200
    tcp_keepalives_interval                       : 75
    temp_buffers                                  : 1024
    temp_file_limit                               : -1
    temp_tablespaces                              :
    TimeZone                                      : Etc/UTC
    timezone_abbreviations                        : Default
    trace_notify                                  : off
    trace_recovery_messages                       : log
    trace_sort                                    : off
    track_activities                              : on
    track_activity_query_size                     : 1024
    track_commit_timestamp                        : off
    track_counts                                  : on
    track_functions                               : none
    track_io_timing                               : off
    transaction_deferrable                        : off
    transaction_isolation                         : read committed
    transaction_read_only                         : off
    transform_null_equals                         : off
    unix_socket_directories                       : /var/run/postgresql
    unix_socket_group                             :
    unix_socket_permissions                       : 0777
    update_process_title                          : on
    vacuum_cost_delay                             : 0
    vacuum_cost_limit                             : 200
    vacuum_cost_page_dirty                        : 20
    vacuum_cost_page_hit                          : 1
    vacuum_cost_page_miss                         : 10
    vacuum_defer_cleanup_age                      : 0
    vacuum_freeze_min_age                         : 50000000
    vacuum_freeze_table_age                       : 150000000
    vacuum_multixact_freeze_min_age               : 5000000
    vacuum_multixact_freeze_table_age             : 150000000
    wal_block_size                                : 8192
    wal_buffers                                   : 512
    wal_compression                               : off
    wal_keep_segments                             : 0
    wal_level                                     : minimal
    wal_log_hints                                 : off
    wal_receiver_status_interval                  : 10
    wal_receiver_timeout                          : 60000
    wal_retrieve_retry_interval                   : 5000
    wal_segment_size                              : 2048
    wal_sender_timeout                            : 60000
    wal_sync_method                               : fdatasync
    wal_writer_delay                              : 200
    wal_writer_flush_after                        : 128
    work_mem                                      : 4096
    xmlbinary                                     : base64
    xmloption                                     : content
    zero_damaged_pages                            : off

    ##### --- Processes start up command --- ####
    No postgres process found

Minimum auth role
^^^^^^^^^^^^^^^^^

This program needs to run some commands like ``getShardMap`` and to be able to run those commands
it needs to run under a user with the ``clusterAdmin`` or ``root`` built-in roles.
