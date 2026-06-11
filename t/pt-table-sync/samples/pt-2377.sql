DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE `test_table` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `data` JSON NOT NULL
) ENGINE=InnoDB;

INSERT INTO
  `test_table` (`data`)
VALUES
  ('{"name": "Müller"}'),
  ('{"reaction": "哈哈"}');
