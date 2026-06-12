SET innodb_lock_wait_timeout=30;
BEGIN;
UPDATE test.t1 SET f1=3;
