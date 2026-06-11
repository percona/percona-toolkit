DROP DATABASE IF EXISTS pt_ts;
CREATE DATABASE pt_ts;
USE pt_ts;

CREATE TABLE `test_table` (
  `test_table_id` binary(16) NOT NULL,
  `test_table_number` int(11) NOT NULL,
  PRIMARY KEY (`test_table_id`,`test_table_number`)
) ENGINE=InnoDB;

INSERT INTO test_table VALUES (unhex(replace('00002fac-2166-493f-b97c-634ef9d714f3','-','')), (FLOOR( 1 + RAND( ) *1000000 )));
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;
INSERT INTO test_table SELECT unhex(replace(uuid(),'-','')), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table;

CREATE TABLE `test_table_char` (
    `test_table_id` char(32) NOT NULL,
    `test_table_number` int(11) NOT NULL,
    PRIMARY KEY (`test_table_id`,`test_table_number`)
) ENGINE=InnoDB;

INSERT INTO test_table_char VALUES (replace('00002fac-2166-493f-b97c-634ef9d714f3','-',''), (FLOOR( 1 + RAND( ) *1000000 )));
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
INSERT INTO test_table_char SELECT replace(uuid(),'-',''), (FLOOR( 1 + RAND( ) *1000000 )) FROM test_table_char;
