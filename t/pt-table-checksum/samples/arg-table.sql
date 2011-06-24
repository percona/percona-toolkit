USE test;
DROP TABLE IF EXISTS args;
CREATE TABLE args (
   db  char(64)     NOT NULL,
   tbl char(64)     NOT NULL,
   PRIMARY KEY (db, tbl)
);
