CREATE USER 'osc_user'@'%' IDENTIFIED BY 'msandbox';
GRANT ALL PRIVILEGES ON pt_osc.* TO 'osc_user'@'%';
GRANT SUPER ON *.* TO 'osc_user'@'%';
