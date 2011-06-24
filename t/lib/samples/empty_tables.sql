-- These are all empty tables with various columns, engines, etc.
-- They're used to test stuff like issue 672 which requires a least
-- one empty table.
DROP DATABASE IF EXISTS et;
CREATE DATABASE et;
USE et;

CREATE TABLE et1 (
  i int,
  unique index (i)
);

