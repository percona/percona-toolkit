-- Sample table with file-per-table tablespace for testing --remove-tablespace functionality
-- This works with MySQL 5.6+ (file-per-table tablespaces)

CREATE DATABASE IF NOT EXISTS test;
USE test;

-- Create table (will use file-per-table tablespace by default in MySQL 5.6+)
CREATE TABLE test_table (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Insert some test data
INSERT INTO test_table (id, name) VALUES 
(1, 'Alice'),
(2, 'Bob'),
(3, 'Charlie'),
(4, 'David'),
(5, 'Eve');

-- Create another table for testing multiple tables
CREATE TABLE test_table2 (
    id INT PRIMARY KEY,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

INSERT INTO test_table2 (id, description) VALUES 
(1, 'First record'),
(2, 'Second record'),
(3, 'Third record'); 