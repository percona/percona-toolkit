DROP TABLE IF EXISTS test.table_1;
DROP TABLE IF EXISTS test.table_1_dest;

SET NAMES utf8mb4;

CREATE TABLE test.table_1 (
    id int(11) NOT NULL,
    c1 varchar(20) DEFAULT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO test.table_1 VALUES(1, 'I love MySQL! 🐬');

CREATE TABLE test.table_1_dest (
    id int(11) NOT NULL,
    c1 varchar(10) DEFAULT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
