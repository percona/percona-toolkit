drop database if exists osc;
create database osc;
use osc;
create table t (
  i int,
  index (i)
);

insert into t values
   (1),
   (2),
   (3),
   (10),
   (11),
   (12),

   -- 15 dupes
   (13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),(13),

   (24),
   (101),
   (102),
   (103);

create table t2 (
  c char,
  index (c)
);

insert into t2 values
  ('a'), ('a'), ('a'), ('a'), ('a'), ('a'), ('a'), ('b'), ('b'), ('b'), ('c'),
  ('c'), ('d'), ('d'), ('d'), ('d'),
  ('e'), ('f'), ('g');
