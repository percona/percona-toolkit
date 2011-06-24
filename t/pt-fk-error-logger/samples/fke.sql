-- This will cause a foreign key error.

DROP TABLE IF EXISTS child;
DROP TABLE IF EXISTS parent;

CREATE TABLE parent (
   id INT NOT NULL,
   PRIMARY KEY (id)
) ENGINE=INNODB;


CREATE TABLE child (
   id INT,
   parent_id INT,
   INDEX par_ind (parent_id),
   FOREIGN KEY (parent_id) REFERENCES parent(id)
) ENGINE=INNODB;

INSERT INTO parent VALUES (1), (2), (3);
INSERT INTO child VALUES (1, 9);  -- Error!
