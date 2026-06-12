STOP REPLICA FOR CHANNEL '';
SET @@GLOBAL.ENFORCE_GTID_CONSISTENCY=ON;
SET @@GLOBAL.GTID_MODE = OFF_PERMISSIVE;
SET @@GLOBAL.GTID_MODE = ON_PERMISSIVE;
SET @@GLOBAL.GTID_MODE = ON;

CHANGE REPLICATION SOURCE TO source_host='127.0.0.1', source_port=2900, source_user='msandbox', source_password='msandbox', source_auto_position=1 FOR CHANNEL 'sourcechan1';

CHANGE REPLICATION SOURCE TO source_host='127.0.0.1', source_port=2901, source_user='msandbox', source_password='msandbox', source_auto_position=1 FOR CHANNEL 'sourcechan2';

START REPLICA for channel 'sourcechan1';
START REPLICA for channel 'sourcechan2';

