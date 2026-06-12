DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE aaa (
  id int NOT NULL AUTO_INCREMENT,
  a int DEFAULT 0,
  b int DEFAULT 0,
  x int DEFAULT 0,
  z int DEFAULT NULL,
  PRIMARY KEY (`id`)
);

CREATE TABLE bbb (
  id int NOT NULL AUTO_INCREMENT,
  aaa_id int DEFAULT NULL,
  c int DEFAULT 0,
  d int DEFAULT 0,
  x int DEFAULT 0,
  modification_date datetime(3),
  PRIMARY KEY (`id`),
  CONSTRAINT `FK_aaa_id` FOREIGN KEY (`aaa_id`) REFERENCES aaa (`id`) 
);

CREATE TRIGGER before_aaa_upd1 BEFORE UPDATE ON aaa FOR EACH ROW set new.a = old.a+1;
CREATE TRIGGER before_aaa_upd2 BEFORE UPDATE ON aaa FOR EACH ROW set new.b = old.b+1;
CREATE TRIGGER after_aaa_upd3 AFTER UPDATE ON aaa FOR EACH ROW update bbb set c = c+1 WHERE aaa_id = NEW.id;
CREATE TRIGGER after_aaa_upd4 AFTER UPDATE ON aaa FOR EACH ROW update bbb set d = d+1 WHERE aaa_id = NEW.id;

DELIMITER $$
CREATE TRIGGER before_aaa_upd5 BEFORE UPDATE ON aaa FOR EACH ROW 	BEGIN UPDATE bbb SET modification_date = UTC_TIMESTAMP(3) WHERE aaa_id = NEW.id; END;
$$
CREATE TRIGGER after_aaa_upd6 AFTER UPDATE ON aaa FOR EACH ROW 	BEGIN UPDATE bbb SET x = x+1 WHERE aaa_id = NEW.id; END;
$$
DELIMITER ;

INSERT INTO aaa (x) VALUES (10),(20),(30),(40),(50);
INSERT INTO bbb (aaa_id) VALUES (1), (2), (3), (3);
-- UPDATE aaa SET z=id-1 WHERE id=2;
