USE sakila;
CREATE TRIGGER triggers_migration_test
BEFORE
-- a comment here
  INSERT ON film 
-- just to make things harder
  FOR EACH ROW SET NEW.length = 60  
-- for pt_osc
;
