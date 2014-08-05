drop database if exists bug_1340728;
create database bug_1340728;
use bug_1340728;

CREATE TABLE `test` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` char(2) NOT NULL,
  PRIMARY KEY (`id`) USING HASH
) ENGINE=MEMORY DEFAULT CHARSET=latin1;

