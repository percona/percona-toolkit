-- These test tables and rows are meant to be used
-- with the mk-log-player sample logs. The sample
-- logs can (should be able to be) played against
-- these dbs and tbls.
--
-- !!! Please Remember !!!
-- If you change even the smallest thing in this file,
-- you must verfiy that the tests still pass. The tests
-- rely closely on these values.
-- Thank you. :-)

DROP DATABASE IF EXISTS mk_log_player_1;
CREATE DATABASE mk_log_player_1;
USE mk_log_player_1;
DROP TABLE IF EXISTS tbl1;
CREATE TABLE tbl1 (
   a INT
);
INSERT INTO tbl1 VALUES (1),(3),(5),(7),(9),(11),(13),(15),(17),(19),(21),(NULL),(0),(-10),(492),(4),(-20);

DROP DATABASE IF EXISTS mk_log_player_2;
CREATE DATABASE mk_log_player_2;
USE mk_log_player_2;
DROP TABLE IF EXISTS tbl2;
CREATE TABLE tbl2 (
   a INT
);
INSERT INTO tbl2 VALUES (2),(4),(6),(8),(10),(12),(14),(16),(18),(20),(22),(NULL);
