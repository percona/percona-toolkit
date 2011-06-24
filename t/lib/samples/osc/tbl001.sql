DROP DATABASE IF EXISTS osc;
CREATE DATABASE osc;
USE osc;

CREATE TABLE t (
   id INT UNSIGNED PRIMARY KEY,
   c  VARCHAR(16)
) ENGINE=InnoDB;

CREATE TABLE __new_t LIKE t;

INSERT INTO t VALUES (1, 'a'), (2, 'b'), (3, 'c'), (4, 'd'), (5, 'e');

