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

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

my $output;
my @args = (qw(-F /tmp/12345/my.sandbox.cnf --print), 'D=issue_641,t=lt',
            'D=issue_641,t=rt');

$sb->load_file('master', "t/lib/samples/issue_641.sql");

# #############################################################################
# Issue 641: Make mk-table-sync use hex for binary/blob data
# #############################################################################

$output = output(
   sub { pt_table_sync::main(@args) },
   trf => \&remove_traces,
);

is(
   $output,
   "INSERT INTO `issue_641`.`rt`(`id`, `b`) VALUES ('1', 0x089504E470D0A1A0A0000000D4948445200000079000000750802000000E55AD965000000097048597300000EC300000EC301C76FA8640000200049444154789C4CBB7794246779FFBBF78F7B7EBE466177677772CE3D9D667AA67BA62776CE39545557CE3974EE9EB049AB9556392210414258083);
",
   "--hex-blob on by default (issue 641)"
);

$output = output(
   sub { pt_table_sync::main(@args, '--no-hex-blob') },
   trf => \&remove_traces,
);

unlike(
   $output,
   qr/0x089504E470D0A1A0A0000000D4948445200000079000000750802000000E55AD965000000097048597300000EC300000EC301C76FA8640000200049444154789C4CBB7794246779FFBBF78F7B7EBE466177677772CE3D9D667AA67BA62776CE39545557CE3974EE9EB049AB9556392210414258083/,
   "--no-hex-blob"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
