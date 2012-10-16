--
-- From mysql-5.6.7-rc-linux2.6-x86_64/share/mysql_system_tables.sql
--

CREATE TABLE IF NOT EXISTS mysql.innodb_table_stats (
	database_name			VARCHAR(64) NOT NULL,
	table_name			VARCHAR(64) NOT NULL,
	last_update			TIMESTAMP NOT NULL NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	n_rows				BIGINT UNSIGNED NOT NULL,
	clustered_index_size		BIGINT UNSIGNED NOT NULL,
	sum_of_other_index_sizes	BIGINT UNSIGNED NOT NULL,
	PRIMARY KEY (database_name, table_name)
) ENGINE=INNODB DEFAULT CHARSET=utf8 COLLATE=utf8_bin STATS_PERSISTENT=0;

CREATE TABLE IF NOT EXISTS mysql.innodb_index_stats (
	database_name			VARCHAR(64) NOT NULL,
	table_name			VARCHAR(64) NOT NULL,
	index_name			VARCHAR(64) NOT NULL,
	last_update			TIMESTAMP NOT NULL NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	/* there are at least:
	stat_name='size'
	stat_name='n_leaf_pages'
	stat_name='n_diff_pfx%' */
	stat_name			VARCHAR(64) NOT NULL,
	stat_value			BIGINT UNSIGNED NOT NULL,
	sample_size			BIGINT UNSIGNED,
	stat_description		VARCHAR(1024) NOT NULL,
	PRIMARY KEY (database_name, table_name, index_name, stat_name)
) ENGINE=INNODB DEFAULT CHARSET=utf8 COLLATE=utf8_bin STATS_PERSISTENT=0;
