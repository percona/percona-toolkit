#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

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
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave1_dsn = $sb->dsn_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}

my $o = new OptionParser(
   description => 'Cxn',
   file        => "$trunk/bin/pt-table-checksum",
);
$o->get_specs("$trunk/bin/pt-table-checksum");
$o->get_opts();

# In 2.1, these tests did not set innodb_lock_wait_timeout because
# it was not a --set-vars default but rather its own option handled
# by/in the tool.  In 2.2, the var is a --set-vars default, which
# means it will cause a warning on 5.0 and 5.1, so we remoe the var
# to remove the warning.
my $set_vars = $o->set_vars();
delete $set_vars->{innodb_lock_wait_timeout};
delete $set_vars->{lock_wait_timeout};
$dp->prop('set-vars', $set_vars);

sub make_cxn {
   my (%args) = @_;
   $o->get_opts();
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

my $set_calls = 0;
my $cxn = make_cxn(
   dsn_string => 'h=127.1,P=12345,u=msandbox,p=msandbox',
   set        => sub {
      my ($dbh) = @_;
      $set_calls++;
      $dbh->do("SET \@a := \@a + 1");
   },
);

ok(
   !$cxn->dbh(),
   "New Cxn, dbh not connected yet"
);

is(
   $cxn->name(),
   'h=127.1,P=12345',
   'name() uses DSN if not connected'
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
) or diag(Dumper($row));

test_var_val(
   $cxn->dbh(),
   'wait_timeout',
   '10000',
   test => 'Sets --set-vars',
);

is(
   $set_calls,
   1,
   'Calls set callback'
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
) or diag(Dumper($row));

test_var_val(
   $cxn->dbh(),
   'wait_timeout',
   '10000',
   test => 'Reconnect sets --set-vars',
);

is(
   $set_calls,
   2,
   'Reconnect calls set callback'
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
   },
   "cxn->dsn()"
);

my ($hostname) = $master_dbh->selectrow_array('select @@hostname');
is(
   $cxn->name(),
   $hostname,
   'name() uses @@hostname'
);

# ############################################################################
# Default cxn, should be equivalent to 'h=localhost'.
# ############################################################################
my $default_cxn = make_cxn();
is_deeply(
   $default_cxn->dsn(),
   {
      h => 'localhost',
      P => undef,
      u => undef,
      p => undef,
      A => undef,
      F => undef,
      S => undef,
      D => undef,
      t => undef,
   },
   "Defaults to h=localhost"
);

# But now test if it will inherit just a few standard connection options.
@ARGV = qw(--port 12345);
$default_cxn = make_cxn();
is_deeply(
   $default_cxn->dsn(),
   {
      h => 'localhost',
      P => '12345',
      u => undef,
      p => undef,
      A => undef,
      F => undef,
      S => undef,
      D => undef,
      t => undef,
   },
   "Default cxn inherits default connection options"
);

@ARGV = ();
$o->get_opts();

# #############################################################################
# The parent of a forked Cxn should not disconnect the dbh in DESTORY
# because the child still has access to it.
# #############################################################################

my $sync_file = "/tmp/pt-cxn-sync.$PID";
my $outfile   = "/tmp/pt-cxn-outfile.$PID";

my $pid;
{
   my $parent_cxn = make_cxn(
      dsn_string => 'h=127.1,P=12345,u=msandbox,p=msandbox',
      parent     => 1,
   );
   $parent_cxn->connect();

   $pid = fork();
   if ( defined($pid) && $pid == 0 ) {
      # I am the child.
      # Wait for the parent to leave this code block which will cause
      # the $parent_cxn to be destroyed.
      PerconaTest::wait_for_files($sync_file);
      $parent_cxn->{parent} = 0;
      eval {
         $parent_cxn->dbh->do("SELECT 123 INTO OUTFILE '$outfile'");
         $parent_cxn->dbh->disconnect();
      };
      warn $EVAL_ERROR if $EVAL_ERROR;
      exit;
   }
}

# Let the child know that we (the parent) have left that ^ code block,
# so our copy of $parent_cxn has been destroyed, but hopefully the child's
# copy is still alive, i.e. has an active/not-disconnected dbh.
diag(`touch $sync_file`);

# Wait for the child.
waitpid($pid, 0);

ok(
   -f $outfile,
   "Child created outfile"
);

my $output = `cat $outfile 2>/dev/null`;

is(
   $output,
   "123\n",
   "Child executed query"
);

unlink $sync_file if -f $sync_file;
unlink $outfile if -f $outfile;

# #############################################################################
# Re-connect with new DSN.
# #############################################################################

SKIP: {
   skip "Cannot connect to slave1", 4 unless $slave1_dbh;

   $cxn = make_cxn(
      dsn_string => 'h=127.1,P=12345,u=msandbox,p=msandbox',
   );

   $cxn->connect();
   ok(
      $cxn->dbh()->ping(),
      "First connect()"
   );

   ($row) = $cxn->dbh()->selectrow_hashref('SHOW SLAVE STATUS');
   ok(
      !defined $row,
      "First connect() to master"
   ) or diag(Dumper($row));

   $cxn->dbh->disconnect();
   $cxn->connect(dsn => $dp->parse($slave1_dsn));

   ok(
      $cxn->dbh()->ping(),
      "Re-connect connect()"
   );

   ($row) = $cxn->dbh()->selectrow_hashref('SHOW SLAVE STATUS');
   ok(
      $row,
      "Re-connect connect(slave_dsn) to slave"
   ) or diag(Dumper($row));

   $cxn->dbh->disconnect();
   $cxn->connect();

   ok(
      $cxn->dbh()->ping(),
      "Re-re-connect connect()"
   );

   ($row) = $cxn->dbh()->selectrow_hashref('SHOW SLAVE STATUS');
   ok(
      $row,
      "Re-re-connect connect() to slave"
   ) or diag(Dumper($row));
}

# #############################################################################
# Done.
# #############################################################################
$master_dbh->disconnect() if $master_dbh;
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
