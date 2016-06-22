CREATE DATABASE IF NOT EXISTS test;
USE test;
DROP TABLE IF EXISTS t1;
DROP TABLE IF EXISTS t2;

create table t1 (a int, b int, key (a),key(b));
create table t2 like t1;

insert into t1 (a,b) values (10,5);
insert into t1 (a,b) values (10,4);
insert into t1 (a,b) values (10,3);
insert into t1 (a,b) values (10,2);
insert into t1 (a,b) values (10,1);
