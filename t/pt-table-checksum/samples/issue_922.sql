USE test;
DROP TABLE IF EXISTS t;
CREATE TABLE t (
   i int not null auto_increment primary key,
   c varchar(32)
);
INSERT INTO test.t VALUES (null, 'aa'), (null, 'ab'), (null, 'ac'), (null, 'ad');
SET SQL_LOG_BIN=0;
INSERT INTO test.t VALUES (null, 'zz'), (null, 'zb');
SET SQL_LOG_BIN=1;
