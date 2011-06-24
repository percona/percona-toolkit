USE test;
DROP TABLE IF EXISTS issue_1166;
CREATE TABLE issue_1166 (
   id   INT NOT NULL,
   name varchar(8),
   INDEX (id)
);
INSERT INTO issue_1166 VALUES (1, "I'm"), (2, "a"), (3, "little"), (4, "teapot"), (5, "short"), (6, "and"), (7, "stout");
