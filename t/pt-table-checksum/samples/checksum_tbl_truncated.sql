CREATE DATABASE IF NOT EXISTS test;
USE test;
DROP TABLE IF EXISTS checksum;
CREATE TABLE checksum (
 db         char(64)     NOT NULL,
 tbl        char(64)     NOT NULL,
 chunk      int          NOT NULL,
 boundaries char(1)      NOT NULL, -- should cause a truncation
 this_crc   char(40)     NOT NULL,
 this_cnt   int          NOT NULL,
 master_crc char(40)         NULL,
 master_cnt int              NULL,
 ts         timestamp    NOT NULL,
 PRIMARY KEY (db, tbl, chunk)
);
