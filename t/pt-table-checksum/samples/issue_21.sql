USE test;
DROP TABLE IF EXISTS issue_21;
CREATE TABLE issue_21 (
   a  INT,
   b  CHAR(1)
) ENGINE=InnoDB;
INSERT INTO issue_21 VALUES (1,'a'),(2,'b'),(3,'c'),(4,'d'),(5,'e');
