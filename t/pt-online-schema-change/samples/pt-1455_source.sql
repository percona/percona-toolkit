DROP DATABASE IF EXISTS employees;
CREATE DATABASE employees;
-- This table should be replicated
CREATE TABLE employees.t1 (
    id INT AUTO_INCREMENT PRIMARY KEY, 
    f2 INT
) ENGINE=InnoDB;

