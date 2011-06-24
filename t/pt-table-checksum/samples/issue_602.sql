-- Issue 602: mk-table-checksum issue with invalid dates
drop database if exists issue_602;
create database issue_602;
use issue_602;
create table t (
   a int,
   b datetime not null,
   key (b)
);
insert into t VALUES (1, "2010-05-09 00:00:00");
insert into t VALUES (2, "2010-05-08 00:00:00");
insert into t VALUES (3, "2010-05-07 00:00:00");
insert into t VALUES (4, "2010-05-06 00:00:00");
insert into t VALUES (5, "2010-05-05 00:00:00");
insert into t VALUES (6, "2010-05-04 00:00:00");
insert into t VALUES (7, "2010-05-03 00:00:00");
insert into t VALUES (8, "2010-05-02 00:00:00");
insert into t VALUES (9, "2010-05-01 00:00:00");
insert into t VALUES (10, "2010-04-30 00:00:00");

-- invalid datetime
insert into t VALUES (11, '2010-00-09 00:00:00' );

-- like t but used in TableChunker.t to test that first_valid_value()
-- only tries a limited number of next rows.  So most the rows in this
-- table are invalid.
create table t2 (
   a int,
   b datetime not null,
   key (b)
);
insert into t2 VALUES (1, "2010-00-01 00:00:01");
insert into t2 VALUES (2, "2010-00-02 00:00:02");
insert into t2 VALUES (3, "2010-00-03 00:00:03");
insert into t2 VALUES (4, "2010-00-04 00:00:04");
insert into t2 VALUES (5, "2010-00-05 00:00:05");
insert into t2 VALUES (6, "2010-00-06 00:00:06");
insert into t2 VALUES (7, "2010-01-07 00:00:07");
insert into t2 VALUES (7, "2010-01-08 00:00:08");
