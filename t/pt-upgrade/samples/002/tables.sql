DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;
create table t (i int);
insert into t values (1), (2), (3);

DROP DATABASE IF EXISTS tmp_db;
CREATE DATABASE tmp_db;
