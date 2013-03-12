USE test;

-- Increase column size from 8 to 16 so insert.log causes
-- a warning diff (value is truncated on host1).
ALTER TABLE t CHANGE COLUMN username username varchar(16) default NULL;
