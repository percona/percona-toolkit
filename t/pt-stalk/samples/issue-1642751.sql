/* This enables perfomance schema without a server restart */
UPDATE performance_schema.setup_consumers SET ENABLED = 'YES' WHERE NAME = 'events_waits_current';

/* Enable instrumentation */

UPDATE performance_schema.setup_instruments set ENABLED = 'YES', TIMED = 'YES' WHERE NAME = 'wait/lock/metadata/sql/mdl';
UPDATE performance_schema.setup_instruments SET ENABLED = 'YES', TIMED = 'YES' WHERE NAME = 'transaction';
UPDATE performance_schema.setup_consumers SET ENABLED = 'YES' WHERE NAME LIKE 'events_transactions%';
UPDATE performance_schema.setup_consumers SET ENABLED = 'YES' WHERE NAME LIKE '%events_transactions%';
FLUSH TABLES;

CREATE SCHEMA IF NOT EXISTS test;

USE test;
DROP TABLE IF EXISTS t1;
CREATE TABLE t1 (id int) ENGINE=INNODB;

/* Successfuly finished transaction */
SET autocommit=0;
START TRANSACTION;
INSERT INTO t1 VALUES (CEIL(RAND()*10000));
COMMIT;

/* Ongoing transaction */
SET autocommit=0;
START TRANSACTION;
INSERT INTO t1 VALUES (CEIL(RAND()*10000));
/* Wait to let pt-stalk to collect the data and find an ACTIVE transaction */
SELECT SLEEP(11);
COMMIT;

DROP DATABASE IF EXISTS test;
