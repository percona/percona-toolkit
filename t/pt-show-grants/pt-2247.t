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
use SqlModes;
use VersionParser;
require "$trunk/bin/pt-show-grants";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

if ( VersionParser->new($dbh)->flavor !~ m/maria/i ) {
   plan skip_all => "This test requires MariaDB";
}

$sb->wipe_clean($dbh);

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';

diag(`/tmp/12345/use -u root -e "CREATE USER 'sally'\@'%' IDENTIFIED BY 'A005?>6LZe1'"`);

ok(
   `/tmp/12345/use -s -u sally -p'A005?>6LZe1' -e "SELECT 1" 2>/dev/null`,
   'User sally can log in before tests'
);

$output = output(
   sub { pt_show_grants::main('-F', $cnf, qw(--only sally)); }
);

like(
   $output,
   qr/CREATE USER IF NOT EXISTS `sally`@`%`;/,
   'CREATE USER printed'
) or diag($output);

like(
   $output,
   qr/ALTER USER `sally`@`%` IDENTIFIED BY PASSWORD '\*A5C09B5E9542E3C716E3E0A711336D9ABB48D89F';/,
   'ALTER USER printed'
) or diag($output);

diag(`/tmp/12345/use -u root -e "DROP USER 'sally'\@'%'"`);
open(my $pipe, '|-', '/tmp/12345/use -u root');
print $pipe $output;
close($pipe);

ok(
   `/tmp/12345/use -s -u sally -p'A005?>6LZe1' -e "SELECT 1" 2>/dev/null`,
   'User sally can log in'
) or diag($output);

diag(`/tmp/12345/use -u root -e "DROP USER 'sally'\@'%'"`);

diag(`/tmp/12345/use -u root -e "CREATE USER 'sally'\@'%' IDENTIFIED VIA mysql_native_password USING PASSWORD('pwd') OR unix_socket"`);

$output = output(
   sub { pt_show_grants::main('-F', $cnf, qw(--only sally --convert-from-mariadb)); }
);

like(
   $output,
   qr/ALTER USER `sally`@`%` IDENTIFIED WITH auth_socket;/,
   'Conversion works with option --convert-from-mariadb'
) or diag($output);

unlike(
   $output,
   qr/Option --convert-MariaDB is deprecated and will be removed in future versions. Use --convert-from-mariadb instead/,
   'Deprecation warning not printed if option --convert-from-mariadb was used'
) or diag($output);

($output, my $exit_code) = full_output(
   sub { pt_show_grants::main('-F', $cnf, qw(--only sally --convert-MariaDB)); },
   stderr => 1,
);

like(
   $output,
   qr/ALTER USER `sally`@`%` IDENTIFIED WITH auth_socket;/,
   'Conversion works with deprecated option --convert-MariaDB'
) or diag($output);

like(
   $output,
   qr/Option --convert-MariaDB is deprecated and will be removed in future versions. Use --convert-from-mariadb instead/,
   'Deprecation warning printed if option --convert-MariaDB was used'
) or diag($output);

$output = output(
   sub { pt_show_grants::main('-F', $cnf, qw(--only sally)); }
);

unlike(
   $output,
   qr/ALTER USER `sally`@`%` IDENTIFIED WITH auth_socket;/,
   'Original statement printed if option --convert-from-mariadb was not specified'
) or diag($output);


diag(`/tmp/12345/use -u root -e "DROP USER 'sally'\@'%'"`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
