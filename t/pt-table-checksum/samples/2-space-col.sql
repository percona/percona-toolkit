drop database if exists test;
create database test;
use test;
create table t (
  id int auto_increment primary key,
  `a  b` int not null  -- 2 spaces between a and b
);
insert into t values (null, 1),(null, 2),(null, 3),(null, 4),(null, 5),(null, 6),(null, 7),(null, 8),(null, 9),(null, 10);
