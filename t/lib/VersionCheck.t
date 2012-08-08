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
use Data::Dumper;

use VersionCheck;
use DSNParser;
use Sandbox;
use PerconaTest;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

my $vc = VersionCheck->new();

sub test_v {
   my (%args) = @_;

   my $items = $vc->parse_server_response(
      response => $args{response},
   );
   is_deeply(
      $items,
      $args{items},
      "$args{name} items"
   );

   my $versions = $vc->get_versions(
      items => $items,
      dbh   => $dbh,
   );
   is_deeply(
      $versions,
      $args{versions},
      "$args{name} versions"
   );

   return;
}

test_v(
   name     => "Perl version",
   response => "Perl;perl_variable;PERL_VERSION\n",
   items    => {
      'Perl' => {
         item => 'Perl',
         type => 'perl_variable',
         vars => [qw(PERL_VERSION)],
      },
   },
   versions => {
      'Perl' => "$PERL_VERSION",
   },
);

test_v(
   name     => "perl_variable (no args)",
   response => "Data::Dumper;perl_variable\n",
   items    => {
      'Data::Dumper' => {
         item => 'Data::Dumper',
         type => 'perl_variable',
         vars => [],
      },
   },
   versions => {
      'Data::Dumper' => $Data::Dumper::VERSION,
   },
);

my (undef, $mysql_version)
   = $dbh->selectrow_array("SHOW VARIABLES LIKE 'version'");
my (undef, $mysql_distro)
   = $dbh->selectrow_array("SHOW VARIABLES LIKE 'version_comment'");

test_v(
   name     => "mysql_variable",
   response => "MySQL;mysql_variable;version_comment,version\n",
   items    => {
      'MySQL' => {
         item => 'MySQL',
         type => 'mysql_variable',
         vars => [qw(version_comment version)],
      },
   },
   versions => {
      'MySQL' => "$mysql_distro $mysql_version",
   },
);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
exit;
