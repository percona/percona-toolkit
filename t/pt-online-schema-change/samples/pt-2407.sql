CREATE DATABASE pt_2407;

USE pt_2407;

CREATE TABLE t1 (
    c1 int NOT NULL,
    c2 varchar(100) NOT NULL,
    PRIMARY KEY (c1),
    KEY idx (c2)
) ENGINE=InnoDB;

INSERT INTO t1 VALUES(1,1),(2,2),(3,3),(4,4),(5,5);
