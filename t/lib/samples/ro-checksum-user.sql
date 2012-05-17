CREATE USER 'ro_checksum_user'@'%' IDENTIFIED BY 'msandbox';
GRANT SELECT ON sakila.* TO 'ro_checksum_user'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON percona.checksums TO 'ro_checksum_user'@'%';
