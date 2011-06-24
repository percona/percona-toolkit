USE test;
DROP TABLE IF EXISTS query_review;
CREATE TABLE query_review (
  checksum     BIGINT UNSIGNED NOT NULL PRIMARY KEY, -- md5 of fingerprint
  fingerprint  TEXT NOT NULL,
  sample       TEXT NOT NULL,
  first_seen   DATETIME,
  last_seen    DATETIME,
  reviewed_by  VARCHAR(20),
  reviewed_on  DATETIME,
  comments     VARCHAR(100)
);

INSERT INTO query_review VALUES
(11676753765851784517, 'select col from foo_tbl', 'SELECT col FROM foo_tbl', '2007-12-18 11:48:27', '2007-12-18 11:48:27', NULL, NULL, NULL),
(15334040482108055940, 'select col from bar_tbl', 'SELECT col FROM bar_tbl', '2005-12-19 16:56:31', '2006-12-20 11:48:57', NULL, NULL, NULL);

