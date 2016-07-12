DROP DATABASE IF EXISTS enum_fields_db;

CREATE DATABASE enum_fields_db;

USE enum_fields_db;

DROP TABLE IF EXISTS enum_fields_db.rgb;

CREATE TABLE `enum_fields_db`.`rgb` (
   `name` VARCHAR(20) NOT NULL,
   `hex_code` ENUM('0xFF0000', '0x00FF00', '0x0000FF') NULL,
   PRIMARY KEY (`name`));


INSERT INTO `enum_fields_db`.`rgb` (`name`, `hex_code`)
VALUES ('red','0xFF0000'), ('green', '0x00FF00');

