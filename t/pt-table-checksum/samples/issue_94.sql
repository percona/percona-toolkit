USE test;
DROP TABLE IF EXISTS `issue_94`;
CREATE TABLE `issue_94` (
   a INT NOT NULL,
   b INT NOT NULL,
   c CHAR(16) NOT NULL,
   INDEX idx (a)
);

INSERT INTO issue_94 VALUES (1,2,'apple'),(3,4,'banana'),(5,6,'kiwi'),(7,8,'orange'),(9,10,'grape'),(11,12,'coconut');
