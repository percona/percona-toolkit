-- Sample table with tablespace for testing --remove-tablespace functionality
-- This requires MySQL 5.7+ for general tablespace support

CREATE DATABASE IF NOT EXISTS test;
USE test;

-- Create a general tablespace first (MySQL 5.7+)
CREATE TABLESPACE test_tablespace ADD DATAFILE 'test_tablespace.ibd';

-- Create table with tablespace
CREATE TABLE test_table (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) TABLESPACE test_tablespace;

-- Insert some test data
INSERT INTO test_table (id, name) VALUES 
(1, 'Alice'),
(2, 'Bob'),
(3, 'Charlie'),
(4, 'David'),
(5, 'Eve');

-- Create another table with tablespace for testing multiple tables
CREATE TABLE test_table2 (
    id INT PRIMARY KEY,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) TABLESPACE test_tablespace;

INSERT INTO test_table2 (id, description) VALUES 
(1, 'First record'),
(2, 'Second record'),
(3, 'Third record'); 