DROP DATABASE IF EXISTS dsn_t;
CREATE DATABASE dsn_t;
USE dsn_t;

CREATE TABLE dsns (
  id int auto_increment primary key,
  parent_id int default null,
  dsn varchar(255) not null
);

INSERT INTO dsns VALUES
  (null, null, 'h=127.1,P=12346,u=msandbox,p=msandbox');
