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
   plan tests => 2;
}

my $output;
my $rows;
my $cnf = "/tmp/12345/my.sandbox.cnf";

$sb->load_file('master', 't/pt-archiver/samples/issue_1152.sql');

# #############################################################################
# Bug #903379: --file & --charset could cause warnings and exceptions
# #############################################################################

$output = output(
   sub {
      no warnings "syntax";
      pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=issue_1152,t=t,u=msandbox,p=msandbox',
      '--dest',    'h=127.1,P=12345,D=issue_1152_archive,t=t',
      '--columns', 'a,b,c',
      '--where',   'id = 5',
      qw( --nocheck-columns --replace --commit-each --bulk-insert --bulk-delete 
          --statistics 
          --no-check-charset ),
      '--file', '/tmp/mysql/%Y-%m-%d-%D_%H:%i:%s.%t',
      )
   },
);
ok(1, "pt-archiver with an explicit --file works");

$output = output(
   sub {
      no warnings "syntax";
      pt_archiver::main(
      '--source',  'h=127.1,P=12345,D=issue_1152,t=t,u=msandbox,p=msandbox',
      '--dest',    'h=127.1,P=12345,D=issue_1152_archive,t=t',
      '--columns', 'a,b,c',
      '--where',   'id = 5',
      qw( --nocheck-columns --replace --commit-each --bulk-insert --bulk-delete 
          --statistics 
          --no-check-charset ),
      '--file', '/tmp/mysql/%Y-%m-%d-%D_%H:%i:%s.%t',
      '--charset', 'latin1',
      )
   },
);
ok(1, "pt-archiver with an explicit --file & --charset works, even if the charset isn't official");

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
