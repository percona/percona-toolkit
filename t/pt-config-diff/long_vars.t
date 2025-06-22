#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-config-diff";

require VersionParser;
my $dp   = new DSNParser(opts=>$dsn_opts);
my $sb   = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh  = $sb->get_dbh_for('source');

my ($ver, $reset, $set_short, $set_long);

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

if ( $sandbox_version ge '5.7' ) {
   $reset = q{SET GLOBAL session_track_system_variables = ''};
   $set_short =
      q{SET GLOBAL session_track_system_variables = '}.
      q{activate_all_roles_on_login,admin_address,}.
      q{admin_port,admin_ssl_ca,admin_ssl_capath,admin_ssl_cert,}.
      q{admin_ssl_cipher,admin_ssl_crl,admin_ssl_crlpath,admin_ssl_key,}.
      q{admin_tls_ciphersuites,admin_tls_version,authentication_policy,}.
      q{auto_generate_certs,auto_increment_increment,}.
      q{auto_increment_offset,autocommit,automatic_sp_privileges,}.
      q{back_log,basedir,big_tables,bind_address,binlog_cache_size,}.
      q{binlog_checksum,binlog_ddl_skip_rewrite,}.
      q{binlog_direct_non_transactional_updates,binlog_encryption,}.
      q{binlog_error_action,binlog_expire_logs_auto_purge,}.
      q{binlog_expire_logs_seconds,binlog_format,binlog_group_commit_sync_delay,}.
      q{binlog_group_commit_sync_no_delay_count,binlog_gtid_simple_recovery,}.
      q{binlog_max_flush_queue_time,binlog_order_commits,}.
      q{binlog_rotate_encryption_master_key_at_startup,binlog_row_event_max_size,}.
      q{binlog_row_image,binlog_row_metadata,binlog_row_value_options,}.
      q{binlog_rows_query_log_events,binlog_skip_flush_commands,}.
      q{binlog_space_limit,binlog_stmt_cache_size'};
   $set_long =
      q{SET GLOBAL session_track_system_variables = '}.
      q{activate_all_roles_on_login,admin_address,}.
      q{admin_port,admin_ssl_ca,admin_ssl_capath,admin_ssl_cert,}.
      q{admin_ssl_cipher,admin_ssl_crl,admin_ssl_crlpath,admin_ssl_key,}.
      q{admin_tls_ciphersuites,admin_tls_version,authentication_policy,}.
      q{auto_generate_certs,auto_increment_increment,}.
      q{auto_increment_offset,autocommit,automatic_sp_privileges,}.
      q{back_log,basedir,big_tables,bind_address,binlog_cache_size,}.
      q{binlog_checksum,binlog_ddl_skip_rewrite,}.
      q{binlog_direct_non_transactional_updates,binlog_encryption,}.
      q{binlog_error_action,binlog_expire_logs_auto_purge,}.
      q{binlog_expire_logs_seconds,binlog_format,binlog_group_commit_sync_delay,}.
      q{binlog_group_commit_sync_no_delay_count,binlog_gtid_simple_recovery,}.
      q{binlog_max_flush_queue_time,binlog_order_commits,}.
      q{binlog_rotate_encryption_master_key_at_startup,binlog_row_event_max_size,}.
      q{binlog_row_image,binlog_row_metadata,binlog_row_value_options,}.
      q{binlog_rows_query_log_events,binlog_skip_flush_commands,}.
      q{binlog_space_limit,binlog_stmt_cache_size,}.
      q{binlog_transaction_compression,binlog_transaction_compression_level_zstd'};
}
else {
   plan skip_all => "Requires MySQL 5.7 or newer";
}

my $output;
my $retval;

$sb->do_as_root('source', $set_short);

$output = output(
   sub { $retval = pt_config_diff::main(
      "${trunk}/t/pt-config-diff/samples/long_vars_1.cnf",
      'h=127.1,P=12345,u=msandbox,p=msandbox')
   },
   stderr => 1,
);

is(
   $retval,
   0,
   "No diff on variable value up to 1024 bytes long"
);

$sb->do_as_root('source', $set_long);

$output = output(
   sub { $retval = pt_config_diff::main(
      "${trunk}/t/pt-config-diff/samples/long_vars_2.cnf",
      'h=127.1,P=12345,u=msandbox,p=msandbox')
   },
   stderr => 1,
);

is(
   $retval,
   0,
   "No diff on variable value longer than 1024 bytes"
);

# #############################################################################
# Done.
# #############################################################################
$sb->do_as_root('source', $reset);

$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
