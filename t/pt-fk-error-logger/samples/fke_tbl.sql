DROP TABLE IF EXISTS foreign_key_errors;
CREATE TABLE foreign_key_errors (
  ts    datetime NOT NULL,
  error text NOT NULL,
  PRIMARY KEY (ts)
)
