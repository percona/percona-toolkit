drop database if exists test;
create database test;
use test;

create table checksum_test(
   a int not null primary key auto_increment
) auto_increment = 5;

insert into checksum_test(a) values (1);

CREATE TABLE checksum (
 db         char(64)     NOT NULL,
 tbl        char(64)     NOT NULL,
 chunk      int          NOT NULL,
 boundaries char(64)     NOT NULL,
 this_crc   char(40)     NOT NULL,
 this_cnt   int          NOT NULL,
 master_crc char(40)         NULL,
 master_cnt int              NULL,
 ts         timestamp    NOT NULL,
 PRIMARY KEY (db, tbl, chunk)
) ENGINE=InnoDB;
