USE test;

-- Add 5 more rows so 01select.log causes a row diff.
INSERT INTO t VALUES
  (null,  'g',  '2013-01-01 00:00:07'),
  (null,  'h',  '2013-01-01 00:00:08'),
  (null,  'i',  '2013-01-01 00:00:09'),
  (null,  'j',  '2013-01-01 00:00:10'),
  (null,  'k',  '2013-01-01 00:00:11');
