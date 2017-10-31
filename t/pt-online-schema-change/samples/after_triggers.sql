DROP SCHEMA IF EXISTS test;
CREATE SCHEMA test;

CREATE TABLE test.t1 (
   id INT NOT NULL AUTO_INCREMENT,
   f1 INT,
   f2 VARCHAR(32),
   PRIMARY KEY (id)
);

CREATE TABLE test.t2 LIKE test.t1;

CREATE TABLE test.log (
   ts  TIMESTAMP,
   msg VARCHAR(255)
);


DROP TRIGGER IF EXISTS test.after_insert;
DROP TRIGGER IF EXISTS test.after_update;
DROP TRIGGER IF EXISTS test.after_delete;


CREATE TRIGGER test.after_insert
 AFTER
 -- a comment here
   INSERT ON test.t1
 -- just to make things harder
   FOR EACH ROW INSERT INTO test.log VALUES (NOW(), CONCAT("inserted new row with id: ", NEW.id))
 -- for pt_osc
;

CREATE TRIGGER test.after_insert2
 AFTER
 -- a comment here
   INSERT ON test.t1
 -- just to make things harder
   FOR EACH ROW INSERT INTO test.log VALUES (NOW(), CONCAT("inserted duplicate of new row with id: ", NEW.id))
 -- for pt_osc
;

DELIMITER //

CREATE TRIGGER test.after_update
 AFTER
 -- a comment here
   UPDATE ON test.t1
 -- just to make things harder
   FOR EACH ROW 
   BEGIN
     INSERT INTO test.log VALUES (NOW(), CONCAT("updated row row with id ", OLD.id, " old f1:", OLD.f1, " new f1: ", NEW.f1 ));
     INSERT INTO test.log VALUES (NOW(), CONCAT("updated row row with id ", OLD.id, " old f1:", OLD.f1, " new f1: ", NEW.f1 ));
   END
 -- for pt_osc
//

DELIMITER ;

CREATE TRIGGER test.after_delete
 AFTER
 -- a comment here
   DELETE ON test.t1
 -- just to make things harder
   FOR EACH ROW INSERT INTO test.log VALUES (NOW(), CONCAT("deleted row with id: ", OLD.id))
 -- for pt_osc
;


INSERT INTO test.t1 VALUES
(1, 1, 'a'), (2, 1, 'b'), (3, 1, 'c'), (4, 1, 'd'),
(5, 2, 'e'), (6, 2, 'f'), (7, 3, 'h'), (8, 3, 'g');

DELETE FROM test.t1 WHERE f2 = 'h';
UPDATE test.t1 
   SET f1 = f1 + 1
 WHERE f2 = 'g';

