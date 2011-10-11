#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 14;

use Sandbox;
use OptionParser;
use DSNParser;
use Quoter;
use PerconaTest;
use Cxn;

use Data::Dumper;

my $q   = new Quoter();
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $o  = new OptionParser(description => 'Cxn');
$o->get_specs("$trunk/bin/pt-table-checksum");
$o->get_opts();
$dp->prop('set-vars', $o->get('set-vars'));

sub make_cxn {
   my (%args) = @_;
   return new Cxn(
      OptionParser => $o,
      DSNParser    => $dp,
      %args,
   );
}

sub test_var_val {
   my ($dbh, $var, $val, %args) = @_;

   my @row;
   if ( !$args{user_var} ) { 
      my $sql = "SHOW " . ($args{global} ? "GLOBAL" : "SESSION " )
              . "VARIABLES LIKE '$var'";
      @row = $dbh->selectrow_array($sql);
   }
   else {
      my $sql = "SELECT $var, $var";
      @row = $dbh->selectrow_array($sql);
   }

   if ( $args{ne} ) {
      ok(
         $row[1] ne $val,
         $args{test} || "$var != $val"
      );
   }
   else {
      is(
         $row[1],
         $val,
         $args{test} || "$var = $val"
      );
   }
}

# The default wait_timeout should not be 10000.  Verify this so when
# Cxn sets it, it's not coincidentally 10000, it was actually set.
test_var_val(
   $master_dbh,
   'wait_timeout',
   '10000',
   ne   =>1,
   test => 'Default wait_timeout',
);

my $cxn = make_cxn(
   dsn_string => 'h=127.1,P=12345,u=msandbox,p=msandbox',
   set        => sub {
      my ($dbh) = @_;
      $dbh->do("SET unique_checks=0");
      $dbh->do("SET \@a := \@a + 1");
   },
);

ok(
   !$cxn->dbh(),
   "New Cxn, dbh not connected yet"
);

$cxn->connect();
ok(
   $cxn->dbh()->ping(),
   "cxn->connect()"
);

my ($row) = $cxn->dbh()->selectrow_hashref('SHOW MASTER STATUS');
ok(
   exists $row->{binlog_ignore_db},
   "FetchHashKeyName = NAME_lc",
);

test_var_val(
   $cxn->dbh(),
   'wait_timeout',
   '10000',
   test => 'Sets --set-vars',
);

test_var_val(
   $cxn->dbh(),
   'unique_checks',
   'OFF',
   test => 'Calls set callback',
);

$cxn->dbh()->do("SET \@a := 1");
test_var_val(
   $cxn->dbh(),
   '@a',
   '1',
   user_var => 1,
);

my $first_dbh = $cxn->dbh();
$cxn->connect();
my $second_dbh = $cxn->dbh();

is(
   $first_dbh,
   $second_dbh,
   "Doesn't reconnect the same dbh"
);

test_var_val(
   $cxn->dbh(),
   '@a',
   '1',
   user_var => 1,
   test     => "Doesn't re-set the vars",
);

# Reconnect.
$cxn->dbh()->disconnect();
$cxn->connect();

($row) = $cxn->dbh()->selectrow_hashref('SHOW MASTER STATUS');
ok(
   exists $row->{binlog_ignore_db},
   "Reconnect FetchHashKeyName = NAME_lc",
);

test_var_val(
   $cxn->dbh(),
   'wait_timeout',
   '10000',
   test => 'Reconnect sets --set-vars',
);

test_var_val(
   $cxn->dbh(),
   'unique_checks',
   'OFF',
   test => 'Reconnect calls set callback',
);

test_var_val(
   $cxn->dbh(),
   '@a',
   undef,
   user_var => 1,
   test    => 'Reconnect is a new connection',
);

is_deeply(
   $cxn->dsn(),
   {
      h => '127.1',
      P => '12345',
      u => 'msandbox',
      p => 'msandbox',
      A => undef,
      F => undef,
      S => undef,
      D => undef,
      t => undef,
      n => 'h=127.1,P=12345',
   },
   "cxn->dsn()"
);

# #############################################################################
# Done.
# #############################################################################
$master_dbh->disconnect() if $master_dbh;
exit;
