DROP TABLE IF EXISTS test.table_1;
DROP TABLE IF EXISTS test.table_1_dest;

SET NAMES latin1;

CREATE TABLE test.table_1 (
    id int(11) NOT NULL,
    c1 varchar(20) DEFAULT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO test.table_1 VALUES(1, 'I love MySQL!');

CREATE TABLE test.table_1_dest (
    id int(11) NOT NULL,
    c1 varchar(20) DEFAULT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
