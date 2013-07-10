DROP DATABASE IF EXISTS cardb;
CREATE DATABASE cardb;
USE cardb;
CREATE TABLE t (
  high  INT UNSIGNED NOT NULL,
  low   INT UNSIGNED NOT NULL,
  INDEX a (low),
  INDEX b (high),
  INDEX c (low)
) ENGINE=InnoDB;
INSERT INTO t VALUES
  (1,   1),
  (2,   1),
  (3,   1),
  (4,   1),
  (5,   1),
  (6,   1),
  (7,   1),
  (8,   1),
  (9,   1),
  (10,  1),
  (11,  1),
  (12,  1),
  (13,  1),
  (14,  1),
  (15,  1),
  (16,  1),
  (17,  1),
  (18,  1),
  (19,  1),
  (20,  1),
  (21,  2),
  (22,  2),
  (23,  2),
  (24,  2),
  (25,  2),
  (26,  2),
  (27,  2),
  (28,  2),
  (29,  2),
  (30,  2),
  (31,  2),
  (32,  2),
  (33,  2),
  (34,  2),
  (35,  2),
  (36,  2),
  (37,  2);
ANALYZE TABLE t;
