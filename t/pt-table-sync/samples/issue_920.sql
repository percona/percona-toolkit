drop database if exists issue_920;
create database issue_920;
use issue_920;

CREATE TABLE PK_UK_test (
  id int(10),
  id2 int(10),
  PRIMARY KEY (id),
  UNIQUE KEY id2 (id2)
) ENGINE=InnoDB;

CREATE TABLE PK_UK_test_2 (
  id int(10),
  id2 int(10),
  PRIMARY KEY (id),
  UNIQUE KEY id2 (id2)
) ENGINE=InnoDB;

insert into PK_UK_test(id,id2) VALUES(1,200),(2,100);
