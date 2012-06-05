DROP DATABASE IF EXISTS dsns;
CREATE DATABASE dsns;
USE dsns;

CREATE TABLE dsns (
  id int auto_increment primary key,
  parent_id int default null,
  dsn varchar(255) not null
); 
      
INSERT INTO dsns VALUES
  -- (1, null, 'h=127.1,P=12345,u=msandbox,p=msandbox'), -- master
  (2, 1,    'h=127.1,P=12346,u=msandbox,p=msandbox'),
  (3, 2,    'h=127.1,P=12347,u=msandbox,p=msandbox');

