DROP DATABASE IF EXISTS percona;
CREATE DATABASE percona;
USE percona;
CREATE TABLE checksums (
  db             char(64)     NOT NULL,
  tbl            char(64)     NOT NULL,
  chunk          int          NOT NULL,
  chunk_time     float            NULL,
  chunk_index    varchar(200)     NULL,
  lower_boundary text             NULL,
  upper_boundary text             NULL,
  this_crc       char(40)     NOT NULL,
  this_cnt       int          NOT NULL,
  master_crc     char(40)         NULL,
  master_cnt     int              NULL,
  ts             timestamp    NOT NULL,
  PRIMARY KEY (db, tbl, chunk),
  INDEX ts_db_tbl (ts, db, tbl)
) ENGINE=MyISAM;
