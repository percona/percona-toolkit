DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE `test_table` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `value` INT NOT NULL,
  `derived_value` INT AS (2*`value`)
) ENGINE=InnoDB;

INSERT INTO `test_table` (`value`) VALUES (24);
INSERT INTO `test_table` (`value`) VALUES (42);
