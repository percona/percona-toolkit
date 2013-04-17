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
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 7;
}

my $output;
my @args = ('h=127.1,P=12346,u=msandbox,p=msandbox', qw(--sync-to-master -t test.ascii -v -v --print --chunk-size 30));

$sb->create_dbs($master_dbh, ['test']);
$sb->load_file('master', "t/lib/samples/char-chunking/ascii.sql", "test");
$master_dbh->do('alter table test.ascii drop column `i`');

wait_until(
   sub {
      my $row;
      eval {$row = $slave_dbh->selectall_arrayref("select * from test.ascii");};
      return 1 if $row && @$row > 100;
   },
);

$slave_dbh->do('delete from test.ascii where c like "Zesus%"');

$output = output(
   sub { pt_table_sync::main(@args) },
);

like(
   $output,
   qr/#\s+0\s+4\s+0\s+0\s+Chunk\s+/,
   "Chunks char col"
);
like(
   $output,
   qr/FORCE INDEX \(`c`\)/,
   "Uses char col index"
);
like(
   $output,
   qr/VALUES \('Zesus'\)/,
   "Replaces first value"
);
like(
   $output,
   qr/VALUES \('Zesus!'\)/,
   "Replaces second value"
);
like(
   $output,
   qr/VALUES \('Zesus!!'\)/,
   "Replaces third value"
);
like(
   $output,
   qr/VALUES \('ZESUS!!!'\)/,
   "Replaces fourth value"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
