STOP SLAVE FOR CHANNEL '';
SET GLOBAL master_info_repository = 'TABLE';
SET @@GLOBAL.relay_log_info_repository = 'TABLE';
SET @@GLOBAL.ENFORCE_GTID_CONSISTENCY=ON;
SET @@GLOBAL.GTID_MODE = OFF_PERMISSIVE;
SET @@GLOBAL.GTID_MODE = ON_PERMISSIVE;
SET @@GLOBAL.GTID_MODE = ON;

CHANGE MASTER TO master_host='127.0.0.1', master_port=12345, master_user='msandbox', master_password='msandbox', master_auto_position=1 FOR CHANNEL 'masterchan1';  

CHANGE MASTER TO master_host='127.0.0.1', master_port=12346, master_user='msandbox', master_password='msandbox', master_auto_position=1 FOR CHANNEL 'masterchan2';  

START SLAVE for channel 'masterchan1';
START SLAVE for channel 'masterchan2';

