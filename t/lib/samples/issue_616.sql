DROP DATABASE IF EXISTS issue_616;
CREATE DATABASE issue_616;
USE issue_616;
CREATE TABLE `t` (
  `id` int(11) NOT NULL auto_increment,
  `name` text,
  PRIMARY KEY  (`id`)
);
INSERT INTO issue_616.t VALUES
(1,  'from source'),
(11, 'from source'),
(21, 'from source'),
(22, 'from slave'),
(32, 'from slave'),
(42, 'from slave'),
(31, 'from source'),
(41, 'from source'),
(51, 'from source');
SET SQL_LOG_BIN=0;
DELETE FROM issue_616.t WHERE id IN (22,32,42);
SET SQL_LOG_BIN=1;
