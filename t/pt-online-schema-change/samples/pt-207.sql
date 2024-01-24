CREATE SCHEMA IF NOT EXISTS test;
USE test;
DROP TABLE IF EXISTS t1;
CREATE TABLE `test`.`t1` (
`id` int(11) NOT NULL,
`f2` int(11) DEFAULT NULL,
`f3` varchar(255) CHARACTER SET latin1 COLLATE latin1_german1_ci,
PRIMARY KEY (`id`)
) ENGINE=RocksDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
