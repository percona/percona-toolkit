drop database if exists test2;
create database test2;
use test2;
create table resume2 (
   i int not null unique key
);
insert into test2.resume2 values (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
