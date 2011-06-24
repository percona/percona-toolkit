drop database if exists test;
create database test;
use test;

create table t1 (
  i int not null,
  unique index (i)
) engine=innodb;

insert into t1 values (1);

create table t2 (
  id int not null,
  i  int,
  unique index (id)
) engine=innodb;

insert into t2 values (1,1),(2,2),(3,3),(4,4),(5,5),(6,6),(7,7),(8,8);
