drop database if exists osc;
create database osc;
use osc;
create table t (
  i int,
  index (i)
);

insert into t values
   (1),(2),(3),
   (10),(11),(12),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(24),
   (101),(102),(103);
