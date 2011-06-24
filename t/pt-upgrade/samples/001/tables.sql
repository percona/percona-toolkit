DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;
DROP TABLE IF EXISTS t;
CREATE TABLE `t` (
  `id` int(10) NOT NULL,
  `name` varchar(255) default NULL,
  `last_login` datetime default NULL,
  PRIMARY KEY  (`id`)
);
INSERT INTO t VALUES
  (-1, 'banned',  '2009-11-06 10:37:17'),
  (0,  'admin',   '2001-11-07 12:01:40'),
  (1,  'bob',     '2009-10-07 10:37:47'),
  (2,  'jane',    '2009-11-07 11:37:97'),
  (3,  'susan',   '2009-04-09 10:00:47'),
  (4,  'rick',    '2009-10-03 10:37:22'),
  (5,  'tom',     '2009-12-07 10:37:74');
