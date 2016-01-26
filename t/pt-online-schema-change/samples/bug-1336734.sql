drop database if exists test;
create database test;
use test;

CREATE TABLE lp1336734 (
   id    int primary key,
   name  varchar(20) DEFAULT NULL
);

INSERT INTO lp1336734 VALUES (1, "curly"), (2, "larry") , (3, NULL), (4, "moe");

