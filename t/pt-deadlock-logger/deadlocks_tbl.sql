CREATE TABLE deadlocks (
   server char(20) NOT NULL,
   ts datetime NOT NULL,
   thread int unsigned NOT NULL,
   txn_id bigint unsigned NOT NULL,
   txn_time smallint unsigned NOT NULL,
   user char(16) NOT NULL,
   hostname char(20) NOT NULL,
   ip char(15) NOT NULL, -- alternatively, ip int unsigned NOT NULL
   db char(64) NOT NULL,
   tbl char(64) NOT NULL,
   idx char(64) NOT NULL,
   lock_type char(16) NOT NULL,
   lock_mode char(1) NOT NULL,
   wait_hold char(1) NOT NULL,
   victim tinyint unsigned NOT NULL,
   query text NOT NULL,
   PRIMARY KEY  (server,ts,thread)
) ENGINE=InnoDB;
