DROP DATABASE IF EXISTS bug_1045317;
CREATE DATABASE bug_1045317;
USE bug_1045317;
CREATE TABLE `bits` (
   `id` int,
   `val` ENUM('M','E','H') NOT NULL,
   PRIMARY KEY (`id`)
);
INSERT INTO `bits` VALUES (1, 'M'), (2, 'E'), (3, 'H');
ANALYZE TABLE bits;
