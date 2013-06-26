USE test;
DROP TABLE IF EXISTS truncated_checksums;
CREATE TABLE truncated_checksums (
  db             char(64)     NOT NULL,
  tbl            char(64)     NOT NULL,
  chunk          int          NOT NULL,
  chunk_time     float            NULL,
  chunk_index    varchar(200)     NULL,
  lower_boundary char(1)      NOT NULL,  -- will cause truncation error
  upper_boundary char(1)      NOT NULL,  -- will cause truncation error
  this_crc       char(40)     NOT NULL,
  this_cnt       int          NOT NULL,
  master_crc     char(40)         NULL,
  master_cnt     int              NULL,
  ts             timestamp    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (db, tbl, chunk)
) ENGINE=InnoDB;
