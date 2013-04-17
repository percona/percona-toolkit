DROP DATABASE IF EXISTS pt_find;
CREATE DATABASE pt_find;
USE pt_find;

create table t1 (
  id int not null primary key
) engine=innodb;

create table t2 (
  id int not null primary key
) engine=innodb;

CREATE FUNCTION hello (s CHAR(20))
RETURNS CHAR(50) DETERMINISTIC
RETURN CONCAT('Hello, ',s,'!');

delimiter //

CREATE PROCEDURE simpleproc (OUT param1 INT)
BEGIN
  SELECT COUNT(*) INTO param1 FROM t;
END//

CREATE TRIGGER ins_trg BEFORE INSERT ON t1
  FOR EACH ROW BEGIN
    INSERT INTO t2 VALUES (NEW.id);
  END;
//

delimiter ;
