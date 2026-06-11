DROP DATABASE IF EXISTS junk;
CREATE DATABASE junk;
CREATE TABLE junk.pt_test_100 (
    id1 binary(16), 
    id2 binary(16), 
    PRIMARY KEY(id1, id2)
);


CREATE DATABASE IF NOT EXISTS percona;
CREATE TABLE IF NOT EXISTS percona.checksums (
   db             CHAR(64)     NOT NULL,
   tbl            CHAR(64)     NOT NULL,
   chunk          INT          NOT NULL,
   chunk_time     FLOAT            NULL,
   chunk_index    VARCHAR(200)     NULL,
   lower_boundary TEXT             NULL,
   upper_boundary TEXT             NULL,
   this_crc       CHAR(40)     NOT NULL,
   this_cnt       INT          NOT NULL,
   source_crc     CHAR(40)         NULL,
   source_cnt     INT              NULL,
   ts             TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
   PRIMARY KEY (db, tbl, chunk),
   INDEX ts_db_tbl (ts, db, tbl)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

TRUNCATE TABLE percona.checksums;

ALTER TABLE percona.checksums MODIFY upper_boundary BLOB, MODIFY lower_boundary BLOB;
