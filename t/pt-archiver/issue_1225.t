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
require "$trunk/bin/pt-archiver";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 5;
}

my $output;

# #############################################################################
# Issue 1152: mk-archiver columns option resulting in null archived table data
# #############################################################################
$sb->load_file('master', 't/pt-archiver/samples/issue_1225.sql');

$dbh->do('set names "utf8"');
my $original_rows = $dbh->selectall_arrayref('select c from issue_1225.t limit 2');
is_deeply(
   $original_rows,
   [  ['が'],  # Your terminal must be UTF8 to see this Japanese character.
      ['が'],
   ],
   "Inserted UTF8 data"
);

throws_ok(
   sub { pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=issue_1225,t=t,u=msandbox,p=msandbox',
      '--dest',    't=a',
      qw(--where 1=1 --purge))
   },
   qr/Character set mismatch/,
   "--check-charset"
);

$output = output(
   sub { pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=issue_1225,t=t,u=msandbox,p=msandbox',
      '--dest',    't=a',
      qw(--no-check-charset --where 1=1 --purge))
   },
);

my $archived_rows = $dbh->selectall_arrayref('select c from issue_1225.a limit 2');

ok(
   $original_rows->[0]->[0] ne $archived_rows->[0]->[0],
   "UTF8 characters lost when cxn isn't also UTF8"
);

$sb->load_file('master', 't/pt-archiver/samples/issue_1225.sql');

$output = output(
   sub { pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=issue_1225,t=t,u=msandbox,p=msandbox',
      '--dest',    't=a',
      qw(--where 1=1 --purge -A utf8)) # -A utf8 makes it work
   },
);

$archived_rows = $dbh->selectall_arrayref('select c from issue_1225.a limit 2');

is_deeply(
   $original_rows,
   $archived_rows,
   "UTF8 characters preserved when cxn is also UTF8"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
