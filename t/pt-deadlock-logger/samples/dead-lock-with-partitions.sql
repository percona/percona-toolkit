drop database if exists test;
create database test;
use test;

CREATE TABLE dl (
  id       INT NOT NULL,
  store_id INT NOT NULL,
  a        INT NOT NULL,
  primary key (id, store_id),
  unique key (store_id)
) ENGINE=InnoDB

PARTITION BY RANGE (store_id) (
  PARTITION p0 VALUES LESS THAN (6),
  PARTITION p1 VALUES LESS THAN (11)
);

insert into test.dl values
  (1, 1, 0), (2, 2, 0), (3, 3, 0), (4, 4, 1), (5, 5, 1), (6, 6, 1);
