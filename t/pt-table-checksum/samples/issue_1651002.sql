
create database if not exists test;
use test;

drop table if exists test1;
drop table if exists test2;
drop table if exists checksums;

CREATE TABLE checksums (
   db             CHAR(64)     NOT NULL,
   tbl            CHAR(64)     NOT NULL,
   chunk          INT          NOT NULL,
   chunk_time     FLOAT            NULL,
   chunk_index    VARCHAR(200)     NULL,
   lower_boundary TEXT             NULL,
   upper_boundary TEXT             NULL,
   this_crc       CHAR(40)     NOT NULL,
   this_cnt       INT          NOT NULL,
   master_crc     CHAR(40)         NULL,
   master_cnt     INT              NULL,
   ts             TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
   PRIMARY KEY (db, tbl, chunk),
   INDEX ts_db_tbl (ts, db, tbl)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

create table test1(
   a int not null,
   b char(2) not null,
   primary key(a, b)
) ENGINE=INNODB;

create table test2(
   a int not null,
   b char(2) not null,
   primary key(a, b)
) ENGINE=INNODB;

insert into test1 values(1, 'en'), (2, 'ca');

drop table if exists test3, test4;
create table test3 (
  id int not null primary key,
  name varchar(255)
);
create table test4 (
  id int not null primary key,
  name varchar(255)
);
insert into test3(id, name) values(15034, '51707'),(1, '001');
insert into test4(id, name) values(15034, '051707'),(1, '1');

-- set sql_log_bin=0;
-- DROP USER 'slave_user';
-- set sql_log_bin=1;
-- FLUSH PRIVILEGES;
