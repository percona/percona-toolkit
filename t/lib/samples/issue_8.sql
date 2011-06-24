USE test;
DROP TABLE IF EXISTS `issue_8`;
CREATE TABLE `issue_8` (
   id    INT AUTO_INCREMENT PRIMARY KEY,
   foo   INT NOT NULL DEFAULT 0,
   bar   VARCHAR(64),
   UNIQUE INDEX uidx_foo (foo),
   INDEX idx_bar (bar(32))
);
