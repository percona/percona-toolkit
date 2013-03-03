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

use DSNParser;
use OptionParser;
use PerconaTest;

use Data::Dumper;

my $opts = [
   {
      key => 'A',
      desc => 'Default character set',
      dsn  => 'charset',
      copy => 1,
   },
   {
      key => 'D',
      desc => 'Database to use',
      dsn  => 'database',
      copy => 1,
   },
   {
      key => 'F',
      desc => 'Only read default options from the given file',
      dsn  => 'mysql_read_default_file',
      copy => 1,
   },
   {
      key => 'h',
      desc => 'Connect to host',
      dsn  => 'host',
      copy => 1,
   },
   {
      key => 'p',
      desc => 'Password to use when connecting',
      dsn  => 'password',
      copy => 1,
   },
   {
      key => 'P',
      desc => 'Port number to use for connection',
      dsn  => 'port',
      copy => 1,
   },
   {
      key => 'S',
      desc => 'Socket file to use for connection',
      dsn  => 'mysql_socket',
      copy => 1,
   },
   {
      key => 'u',
      desc => 'User for login if not current user',
      dsn  => 'user',
      copy => 1,
   },
];

my $dp = new DSNParser(opts => $opts);

is_deeply(
   $dp->parse('u=a,p=b'),
   {  u => 'a',
      p => 'b',
      S => undef,
      h => undef,
      P => undef,
      F => undef,
      D => undef,
      A => undef,
   },
   'Basic DSN'
);

is_deeply(
   $dp->parse('S=/tmp/sock'),
   {  u => undef,
      p => undef,
      S => '/tmp/sock',
      h => undef,
      P => undef,
      F => undef,
      D => undef,
      A => undef,
   },
   'Basic DSN with one part'
);

is_deeply(
   $dp->parse('u=a,p=b,A=utf8'),
   {  u => 'a',
      p => 'b',
      S => undef,
      h => undef,
      P => undef,
      F => undef,
      D => undef,
      A => 'utf8',
   },
   'Basic DSN with charset'
);

# The test that was here is no longer needed now because
# all opts must be specified now.

is_deeply(
   $dp->parse('u=a,p=b', { D => 'foo', h => 'me' }, { S => 'bar', h => 'host' } ),
   {  D => 'foo',
      F => undef,
      h => 'me',
      p => 'b',
      P => undef,
      S => 'bar',
      u => 'a',
      A => undef,
   },
   'DSN with defaults'
);

is(
   $dp->as_string(
      $dp->parse('u=a,p=b', { D => 'foo', h => 'me' }, { S => 'bar', h => 'host' } )
   ),
   'D=foo,S=bar,h=me,p=...,u=a',
   'DSN stringified when it gets DSN as arg'
);

is(
   $dp->as_string(
      'D=foo,S=bar,h=me,p=b,u=a',
   ),
   'D=foo,S=bar,h=me,p=b,u=a',
   'DSN stringified when it gets a string as arg'
);

is (
   $dp->as_string({ bez => 'bat', h => 'foo' }),
   'h=foo',
   'DSN stringifies without extra crap',
);

is (
   $dp->as_string({ h=>'localhost', P=>'3306',p=>'omg'}, [qw(h P)]),
   'h=localhost,P=3306',
   'DSN stringifies only requested parts'
);

# The test that was here is no longer need due to issue 55.
# DSN usage comes from the POD now.

$dp->prop('autokey', 'h');
is_deeply(
   $dp->parse('automatic'),
   {  D => undef,
      F => undef,
      h => 'automatic',
      p => undef,
      P => undef,
      S => undef,
      u => undef,
      A => undef,
   },
   'DSN with autokey'
);

$dp->prop('autokey', 'h');
is_deeply(
   $dp->parse('localhost,A=utf8'),
   {  u => undef,
      p => undef,
      S => undef,
      h => 'localhost',
      P => undef,
      F => undef,
      D => undef,
      A => 'utf8',
   },
   'DSN with an explicit key and an autokey',
);

is_deeply(
   $dp->parse('automatic',
      { D => 'foo', h => 'me', p => 'b' },
      { S => 'bar', h => 'host', u => 'a' } ),
   {  D => 'foo',
      F => undef,
      h => 'automatic',
      p => 'b',
      P => undef,
      S => 'bar',
      u => 'a',
      A => undef,
   },
   'DSN with defaults and an autokey'
);

# The test that was here is no longer need due to issue 55.
# DSN usage comes from the POD now.

is_deeply (
   [
      $dp->get_cxn_params(
         $dp->parse(
            'u=a,p=b',
            { D => 'foo', h => 'me' },
            { S => 'bar', h => 'host' } ))
   ],
   [
      'DBI:mysql:foo;host=me;mysql_socket=bar;mysql_read_default_group=client',
      'a',
      'b',
   ],
   'Got connection arguments',
);

is_deeply (
   [
      $dp->get_cxn_params(
         $dp->parse(
            'u=a,p=b,A=foo',
            { D => 'foo', h => 'me' },
            { S => 'bar', h => 'host' } ))
   ],
   [
      'DBI:mysql:foo;host=me;mysql_socket=bar;charset=foo;mysql_read_default_group=client',
      'a',
      'b',
   ],
   'Got connection arguments with charset',
);

# Make sure we can connect to MySQL with a charset
my $d = $dp->parse('h=127.0.0.1,P=12345,A=utf8,u=msandbox,p=msandbox');
my $dbh;
eval {
   $dbh = $dp->get_dbh($dp->get_cxn_params($d), {});
};
SKIP: {
   skip 'Cannot connect to sandbox master', 6 if $EVAL_ERROR;

   $dp->fill_in_dsn($dbh, $d);
   is($d->{P}, 12345, 'Left port alone');
   is($d->{u}, 'msandbox', 'Filled in username');
   is($d->{S}, '/tmp/12345/mysql_sandbox12345.sock', 'Filled in socket');
   is($d->{h}, '127.0.0.1', 'Left hostname alone');

   is_deeply(
      $dbh->selectrow_arrayref('select @@character_set_client, @@character_set_connection, @@character_set_results'),
      [qw(utf8 utf8 utf8)],
      'Set charset'
   );
   $dbh->disconnect();

   # Issue 1282: Enabling utf8 with --charset (-A) is case-sensitive
   # This test really doesn't do anything because the problem is in the line,
   # mysql_enable_utf8 => ($cxn_string =~ m/charset=utf8/ ? 1 : 0),
   # in get_dbh().  That line is part of a hashref declaration so we
   # have no access to it here.  I keep this this test because it allows
   # me to look manually via PTDEBUG and see that  mysql_enable_utf8=>1
   # even if A=UTF8.
   $d = $dp->parse('h=127.0.0.1,P=12345,A=UTF8,u=msandbox,p=msandbox');
   eval {
      $dbh = $dp->get_dbh($dp->get_cxn_params($d), {});
   };
   is_deeply(
      $dbh->selectrow_arrayref('select @@character_set_client, @@character_set_connection, @@character_set_results'),
      [qw(utf8 utf8 utf8)],
      'Set utf8 charset case-insensitively (issue 1282)'
   );
};

$dp->prop('dbidriver', 'Pg');
is_deeply (
   [
      $dp->get_cxn_params(
         {
            u => 'a',
            p => 'b',
            h => 'me',
            D => 'foo',
         },
      )
   ],
   [
      'DBI:Pg:dbname=foo;host=me',
      'a',
      'b',
   ],
   'Got connection arguments for PostgreSQL',
);

$dp->prop('required', { h => 1 } );
throws_ok (
   sub { $dp->parse('u=b') },
   qr/Missing required DSN option 'h' in 'u=b'/,
   'Missing host part',
);

throws_ok (
   sub { $dp->parse('h=foo,Z=moo') },
   qr/Unknown DSN option 'Z' in 'h=foo,Z=moo'/,
   'Extra key',
);

# #############################################################################
# Test parse_options().
# #############################################################################
my $o = new OptionParser(
   description => 'parses command line options.',
   dp          => $dp,
);
$o->_parse_specs(
   { spec => 'defaults-file|F=s', desc => 'defaults file'  },
   { spec => 'password|p=s',      desc => 'password'       },
   { spec => 'host|h=s',          desc => 'host'           },
   { spec => 'port|P=i',          desc => 'port'           },
   { spec => 'socket|S=s',        desc => 'socket'         },
   { spec => 'user|u=s',          desc => 'user'           },
);
@ARGV = qw(--host slave1 --user foo);
$o->get_opts();

is_deeply(
   $dp->parse_options($o),
   {
      D => undef,
      F => undef,
      h => 'slave1',
      p => undef,
      P => undef,
      S => undef,
      u => 'foo',
      A => undef,
   },
   'Parses DSN from OptionParser obj'
);

# #############################################################################
# Test copy().
# #############################################################################

push @$opts, { key => 't', desc => 'table' };
$dp = new DSNParser(opts => $opts);

my $dsn_1 = {
   D => undef,
   F => undef,
   h => 'slave1',
   p => 'p1',
   P => '12345',
   S => undef,
   t => undef,
   u => 'foo',
   A => undef,
};
my $dsn_2 = {
   D => 'test',
   F => undef,
   h => undef,
   p => 'p2',
   P => undef,
   S => undef,
   t => 'tbl',
   u => undef,
   A => undef,
};

is_deeply(
   $dp->copy($dsn_1, $dsn_2),
   {
      D => 'test',
      F => undef,
      h => 'slave1',
      p => 'p2',
      P => '12345',
      S => undef,
      t => 'tbl',
      u => 'foo',
      A => undef,
   },
   'Copy DSN without overwriting destination'
);
is_deeply(
   $dp->copy($dsn_1, $dsn_2, overwrite=>1),
   {
      D => 'test',
      F => undef,
      h => 'slave1',
      p => 'p1',
      P => '12345',
      S => undef,
      t => 'tbl',
      u => 'foo',
      A => undef,
   },
   'Copy DSN and overwrite destination'
);

pop @$opts; # Remove t part.

# #############################################################################
# Issue 93: DBI error messages can include full SQL
# #############################################################################
SKIP: {
   skip 'ShowErrorStatement requires DBD::mysql 4.003', 1 unless $DBD::mysql::VERSION ge '4.003';
   skip 'Cannot connect to sandbox master', 1 unless $dbh;
   eval { $dbh->do('SELECT * FROM doesnt.exist WHERE foo = 1'); };
   like(
      $EVAL_ERROR,
      qr/SELECT \* FROM doesnt.exist WHERE foo = 1/,
      'Includes SQL in error message (issue 93)'
   );
};


# #############################################################################
# Issue 597: mk-slave-prefetch ignores --set-vars
# #############################################################################

# This affects all scripts because prop() doesn't match what get_dbh() does.
SKIP: {
   skip 'Cannot connect to sandbox master', 1 unless $dbh;
   $dbh->do('SET @@global.wait_timeout=1');

   # This dbh is going to timeout too during this test so close
   # it now else we'll get an error.
   $dbh->disconnect();

   $dp = new DSNParser(opts => $opts);
   $dp->prop('set-vars', { wait_timeout => { val => 1000, default => 1}});
   $d  = $dp->parse('h=127.0.0.1,P=12345,A=utf8,u=msandbox,p=msandbox');
   my $dbh2 = $dp->get_dbh($dp->get_cxn_params($d), {mysql_use_result=>1});
   sleep 2;
   eval {
      $dbh2->do('SELECT DATABASE()');
   };
   is(
      $EVAL_ERROR,
      '',
      'SET vars (issue 597)'
   );
   $dbh2->disconnect();

   # Have to reconnect $dbh since it timedout too.
   $dbh = $dp->get_dbh($dp->get_cxn_params($d), {});
   $dbh->do('SET @@global.wait_timeout=28800');
};

# #############################################################################
# Issue 801: DSNParser clobbers SQL_MODE
# #############################################################################
diag('Setting SQL mode globally on 12345');
my $old_mode = `/tmp/12345/use -ss -e 'select \@\@sql_mode'`;
chomp $old_mode;
diag("Old SQL mode: $old_mode");
diag(`/tmp/12345/use -e 'set global sql_mode=no_zero_date'`);
my $new_mode = `/tmp/12345/use -ss -e 'select \@\@sql_mode'`;
chomp $new_mode;
diag("New SQL mode: $new_mode");
my $dsn = $dp->parse('h=127.1,P=12345,u=msandbox,p=msandbox');
my $mdbh = $dp->get_dbh($dp->get_cxn_params($dsn), {});

my $row = $mdbh->selectrow_arrayref('select @@sql_mode');
is(
   $row->[0],
   'NO_AUTO_VALUE_ON_ZERO,NO_ZERO_DATE',
   "Did not clobber server SQL mode"
);
diag(`/tmp/12345/use -e "set global sql_mode='$old_mode'"`);
$mdbh->disconnect;

# #############################################################################
# Passwords with commas don't work, expose part of password
# https://bugs.launchpad.net/percona-toolkit/+bug/886077
# #############################################################################

sub test_password_comma {
   my ($dsn_string, $pass, $port, $name) = @_;
   my $dsn = $dp->parse($dsn_string);
   is_deeply(
      $dsn,
      {  u => 'a',
         p => $pass,
         S => undef,
         h => undef,
         P => $port,
         F => undef,
         D => undef,
         A => undef,
      },
      "$name (bug 886077)"
   ) or diag(Dumper($dsn));
}

my @password_commas = (
   ['u=a,p=foo\,xxx,P=12345', 'foo,xxx', 12345, 'Pass with comma'],
   ['u=a,p=foo\,xxx',         'foo,xxx', undef, 'Pass with comma, last part'],
   ['u=a,p=foo\,,P=12345',    'foo,',    12345, 'Pass ends with comma'],
   ['u=a,p=foo\,',            'foo,',    undef, 'Pass ends with comma, last part'],
   ['u=a,p=\,,P=12345',       ',',       12345, 'Pass is a comma'],
);
foreach my $password_comma ( @password_commas ) {
   test_password_comma(@$password_comma);
}

sub test_password_comma_with_auto {
   my ($dsn_string, $pass, $port, $name) = @_;
   my $dsn = $dp->parse($dsn_string);
   is_deeply(
      $dsn,
      {  u => undef,
         p => $pass,
         S => undef,
         h => 'host',
         P => $port,
         F => undef,
         D => undef,
         A => undef,
      },
      "$name (bug 886077)"
   ) or diag(Dumper($dsn));
}

@password_commas = (
   ['host,p=a\,z,P=9', 'a,z', 9, 'Comma-pass with leading bareword host'],
   ['p=a\,z,P=9,host', 'a,z', 9, 'Comma-pass with trailing bareword host'],

);
foreach my $password_comma ( @password_commas ) {
   test_password_comma_with_auto(@$password_comma);
}

# #############################################################################
# Bug 984915: SQL calls after creating the dbh aren't checked
# #############################################################################
# Make sure to disconnect any lingering dbhs, since full_output will fork
# and then die, which will cause rollback warnings for connected dbhs.
$dbh->disconnect() if $dbh;

$dsn = $dp->parse('h=127.1,P=12345,u=msandbox,p=msandbox');
my @opts = $dp->get_cxn_params($dsn);
$opts[0] .= ";charset=garbage_eh";
my ($out, undef) = full_output(sub { $dp->get_dbh(@opts, {}) });

like(
   $out,
   qr/\QUnknown character set/,
   "get_dbh dies with an unknown charset"
);

$dp->prop('set-vars',  { time_zoen => { val => 'UTC' }});
$out = output(
   sub {
      my $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), {});
      $dbh->disconnect();
   },
   stderr => 1,
);

like(
   $out,
   qr/\QUnknown system variable 'time_zoen'/,
   "get_dbh dies with an unknown system variable"
);
$dp->prop('set-vars', undef);

# #############################################################################
# Bug 1078887: Don't clobber the sql_mode set by the script with set-vars
# https://bugs.launchpad.net/percona-toolkit/+bug/1078887
# #############################################################################

$dp->prop('set-vars', { sql_mode => { val=>'ANSI_QUOTES' }});
my $sql_mode_dbh = $dp->get_dbh($dp->get_cxn_params($dsn), {});

my (undef, $sql_mode) = $sql_mode_dbh->selectrow_array(q{SHOW VARIABLES LIKE 'sql\_mode'});

like(
   $sql_mode,
   qr/NO_AUTO_VALUE_ON_ZERO/,
   "Bug 1078887: --set-vars doesn't clover the sql_mode set by DSNParser"
);

$sql_mode_dbh->disconnect();

# #############################################################################
# LOAD DATA LOCAL INFILE broken in some platforms
# https://bugs.launchpad.net/percona-toolkit/+bug/821715
# #############################################################################

SKIP: {
   skip "LOAD DATA LOCAL INFILE already works here", 1 if $can_load_data;
   local $dsn->{L} = 1;
   my $dbh = $dp->get_dbh( $dp->get_cxn_params( $dsn ) );

   use File::Temp qw(tempfile);

   my ($fh, $filename) = tempfile( 'load_data_test.XXXXXXX', TMPDIR => 1 );
   print { $fh } "42\n";
   close $fh or die "Cannot close $filename: $!";

   $dbh->do(q{DROP DATABASE IF EXISTS bug_821715});
   $dbh->do(q{CREATE DATABASE bug_821715});
   $dbh->do(q{CREATE TABLE IF NOT EXISTS bug_821715.load_data (i int)});

   eval {
      $dbh->do(qq{LOAD DATA LOCAL INFILE '$filename' INTO TABLE bug_821715.load_data});
   };

   is(
      $EVAL_ERROR,
      '',
      "Even though LOCAL INFILE is off by default, the dbhs returned by DSNParser can use it if L => 1"
   );
   
   unlink $filename;

   $dbh->do(q{DROP DATABASE IF EXISTS bug_821715});
   $dbh->disconnect();
}

# #############################################################################
# Done.
# #############################################################################
done_testing;
   
