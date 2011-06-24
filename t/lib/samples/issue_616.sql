DROP DATABASE IF EXISTS issue_616;
CREATE DATABASE issue_616;
USE issue_616;
CREATE TABLE `t` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  PRIMARY KEY  (`id`)
);
INSERT INTO issue_616.t VALUES
(1,  'from master'),
(11, 'from master'),
(21, 'from master'),
(22, 'from slave'),
(32, 'from slave'),
(42, 'from slave'),
(31, 'from master'),
(41, 'from master'),
(51, 'from master');
SET SQL_LOG_BIN=0;
DELETE FROM issue_616.t WHERE id IN (22,32,42);
SET SQL_LOG_BIN=1;
