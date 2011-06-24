USE test;

-- Add more column types in another col_type_N table so that previous
-- tests won't break after being surprised with new colums.

DROP TABLE IF EXISTS col_types_1;
CREATE TABLE col_types_1 (
   id INT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
   i  INT,
   f  FLOAT,
   d  DECIMAL(5,2),
   dt DATETIME,
   ts TIMESTAMP,
   c  char,
   c2 char(15) not null,
   v  varchar(32),
   t  text
);
INSERT INTO col_types_1 VALUES (NULL, 1, 3.14, 5.08, NOW(), NOW(), 'c', 'c2', 'hello world', 'this is text');

