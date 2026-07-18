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
use File::Temp qw(tempfile);

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

if ( $sb->is_cluster_mode ) {
   plan skip_all => 'Not for PXC';
}

my $source_dbh  = $sb->get_dbh_for('source');
my $replica_dbh = $sb->get_dbh_for('replica1');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}
elsif ( !$replica_dbh ) {
   plan skip_all => 'Cannot connect to sandbox replica1';
}
else {
   plan tests => 3;
}

my $source_dsn = 'h=127.0.0.1,P=12345,u=msandbox,p=msandbox';
my ($fh, $tmp_file_name) = tempfile();
close $fh;
unlink $tmp_file_name;

$sb->load_file('source', 't/pt-online-schema-change/samples/basic_no_fks.sql');
$source_dbh->do('CREATE DATABASE IF NOT EXISTS test');
$source_dbh->do('DROP TABLE IF EXISTS test.dynamic_replicas');
$source_dbh->do('CREATE TABLE test.dynamic_replicas (id int primary key, dsn varchar(255) not null)');
$source_dbh->do(q{INSERT INTO test.dynamic_replicas (id, dsn) VALUES (1, 'h=127.0.0.1,P=12346,s=1')});

if ($sandbox_version eq '8.0') {
   $sb->do_as_root('replica1', q/CREATE USER 'replica_user'@'%' IDENTIFIED WITH mysql_native_password BY 'replica_password'/);
}
else {
   $sb->do_as_root('replica1', q/CREATE USER 'replica_user'@'%' IDENTIFIED BY 'replica_password'/);
}
$sb->do_as_root('replica1', q/GRANT REPLICATION CLIENT ON *.* TO 'replica_user'@'%'/);
$sb->do_as_root('replica1', q/GRANT REPLICATION SLAVE ON *.* TO 'replica_user'@'%'/);
$sb->do_as_root('replica1', q/GRANT ALL ON pt_osc.* TO 'replica_user'@'%'/);
$sb->do_as_root('replica1', q/FLUSH PRIVILEGES/);

# Force the DSN-discovered replica to require dedicated credentials.
$sb->do_as_root('replica1', q/RENAME USER 'msandbox'@'%' TO 'msandbox_old'@'%'/);
$sb->do_as_root('replica1', q/FLUSH PRIVILEGES/);

my $base_args = "$source_dsn,D=pt_osc,t=t --execute --alter 'ENGINE=InnoDB' "
              . "--recursion-method=dsn=D=test,t=dynamic_replicas --chunk-size 1 "
              . "--max-lag 1 --progress time,5 --pid $tmp_file_name";

my $output = `$trunk/bin/pt-online-schema-change $base_args 2>&1`;

like(
   $output,
   qr/Access denied for user 'msandbox'/,
   'Without --replica-user/--replica-password, dsn recursion replica auth fails'
) or diag($output);

$output = `$trunk/bin/pt-online-schema-change $base_args --replica-user replica_user --replica-password replica_password 2>&1`;

like(
   $output,
   qr/Successfully altered `pt_osc`.`t`/,
   '--replica-user/--replica-password allow dsn recursion replica auth'
) or diag($output);

$sb->do_as_root('replica1', q/RENAME USER 'msandbox_old'@'%' TO 'msandbox'@'%'/);
$sb->do_as_root('replica1', q/DROP USER 'replica_user'@'%'/);
$sb->do_as_root('replica1', q/FLUSH PRIVILEGES/);

$sb->wipe_clean($source_dbh);
ok($sb->ok(), 'Sandbox servers') or BAIL_OUT(__FILE__ . ' broke the sandbox');

exit;