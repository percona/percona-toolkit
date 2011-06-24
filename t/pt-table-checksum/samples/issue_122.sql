USE test;
DROP TABLE IF EXISTS issue_122;
CREATE TABLE issue_122 (
   id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
   a     CHAR(1)
);

DROP TABLE IF EXISTS argtable;
CREATE TABLE argtable (
   db    CHAR(64) NOT NULL,
   tbl   CHAR(64) NOT NULL,
   since CHAR(64),
   PRIMARY KEY (db, tbl)
);
INSERT INTO test.argtable VALUES ('test','issue_122',NULL);
