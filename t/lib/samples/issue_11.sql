USE test;
DROP TABLE IF EXISTS `issue_11`;
CREATE TABLE `issue_11` (
   a INT NOT NULL,
   b INT NOT NULL,
   c INT NOT NULL,
   UNIQUE INDEX idx_a_b (a, b)
);
