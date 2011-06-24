USE test;
DROP TABLE IF EXISTS issue_131_src;
CREATE TABLE issue_131_src (
   id   INT AUTO_INCREMENT PRIMARY KEY,
   name varchar(8)
);
INSERT INTO issue_131_src VALUES (null,'aaa'),(null,'bbb'),(null,'zzz');

DROP TABLE IF EXISTS issue_131_dst;
CREATE TABLE issue_131_dst (
   name varchar(8),
   id   INT AUTO_INCREMENT PRIMARY KEY
);
