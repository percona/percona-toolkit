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
require "$trunk/bin/pt-show-grants";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 12;
}

$sb->wipe_clean($dbh);

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';

$output = output(
   sub { pt_show_grants::main('-F', $cnf, qw(--drop --flush --revoke --separate)); }
);
like(
   $output,
   qr/Grants dumped by/,
   'It lives',
);
like(
   $output,
   qr/REVOKE/,
   'It converted to revokes',
);
like(
   $output,
   qr/FLUSH/,
   'Added FLUSH',
);

like(
   $output,
   qr/DROP/,
   'Added DROP',
);
like(
   $output,
   qr/DELETE/,
   'Added DELETE for older MySQL versions',
);
like(
   $output,
   qr/at \d{4}/,
   'It has a timestamp',
);
like(
   $output,
   qr/^REVOKE ALL PRIVILEGES/m,
   "Revoke statement is correct (bug 821709)"
);

$output = output(
   sub { pt_show_grants::main('-F', $cnf, qw(--no-timestamp --drop --flush --revoke --separate)); }
);
unlike(
   $output,
   qr/at \d{4}/,
   'It has no timestamp',
);

$output = output(
   sub { pt_show_grants::main('-F', $cnf, '--ignore', 'baron,msandbox,root,root@localhost,user'); }
);
unlike(
   $output,
   qr/uninitialized/,
   'Does not die when all users skipped',
);
like(
   $output,
   qr/\d\d:\d\d:\d\d\n\z/,
   'No output when all users skipped'
);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
