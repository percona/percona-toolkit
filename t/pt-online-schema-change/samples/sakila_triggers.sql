USE sakila;

CREATE TABLE IF NOT EXISTS deletes (
  film_id INT
);
  
DROP TRIGGER IF EXISTS sakila.triggers_migration_test_insert;
DROP TRIGGER IF EXISTS sakila.triggers_migration_test_update;
DROP TRIGGER IF EXISTS sakila.triggers_migration_test_delete;

CREATE TRIGGER triggers_migration_test_insert
BEFORE
-- a comment here
  INSERT ON film
-- just to make things harder
  FOR EACH ROW SET NEW.length = 60
-- for pt_osc
;

CREATE TRIGGER triggers_migration_test_update
BEFORE
-- a comment here
  UPDATE ON film
-- just to make things harder
  FOR EACH ROW SET NEW.length = length - 1
-- for pt_osc
;

CREATE TRIGGER triggers_migration_test_delete
BEFORE
-- a comment here
  DELETE ON film
-- just to make things harder
  FOR EACH ROW INSERT INTO sakila.deletes values (film_id)
-- for pt_osc
;
