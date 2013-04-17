#!/usr/bin/perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 31;

use VersionParser;
use PerconaTest;

my $v1 = new_ok "VersionParser", [ "4.1" ], "new from string works";

is(
   "$v1",
   "4.1",
   "object from string stringifies as expected"
);

is(
   $v1->innodb_version,
   'NO',
   'default ->innodb_version is NO'
);

is(
   $v1->flavor(),
   "Unknown",
   "default ->flavor is Unknown"
);

my $v2;
$v2 = new_ok "VersionParser", [ qw( major 5 minor 5 revision 5 ) ], "new from parts works";
is( "$v2", "5.5.5", "..and stringifies correctly" );
$v2 = new_ok "VersionParser", [ { qw( major 5 minor 5 revision 5 ) } ], "new from hashref works";
is( "$v2", "5.5.5", "..and stringifies correctly" );

for my $test (
    [ "5.0.1", "lt", "5.0.2" ],
    [ "5.0",   "eq", "5.0.2" ],
    [ "5.1.0", "gt", "5.0.99" ],
    [ "6",     "gt", "5.9.9" ],
    [ "4",     "ne", "5.0.2" ],
    [ "5.0.1", "ne", "5.0.2" ],
    [ "5.0.1", "eq", "5.0.1" ],
    [ "5.0.1", "eq", "5" ],
    [ "5.0.1", "lt", "6" ],
    [ "5.0.1", "gt", "5.0.09" ],
    # TODO: Should these actually happen?
    # [ "5.0.1"  eq "5.0.10" ]
    # [ "5.0.10" lt "5.0.3" ]
) {
    my ($v, $cmp, $against, $test) = @$test;
    
    cmp_ok( VersionParser->new($v), $cmp, $against, "$v $cmp $against" );
}

my $c = VersionParser->new("5.5.1");

is(
   $c->comment("SET NAMES utf8"),
   "/*!50501 SET NAMES utf8 */",
   "->comment works as expected"
);

is(
   $c->comment('@@hostname,'),
   '/*!50501 @@hostname, */',
   '->comment works with @@variable'
);


is(
   VersionParser->new('5.0.38-Ubuntu_0ubuntu1.1-log')->normalized_version,
   '50038',
   'Parser works on ordinary version',
);

is(
   VersionParser->new('5.5')->normalized_version,
   '50500',
   'Parser works on a simplified version',
);

my $fractional_version = VersionParser->new('5.0.08');

is(
   $fractional_version->revision,
   '0.8',
   'Verson(5.0.08), the revision is 0.8',
);

is(
   "$fractional_version",
   "5.0.08",
   "Version(5.0.08) stringifies to 5.0.08"
);

is(
   $fractional_version->normalized_version(),
   "50000",
   "Version(5.0.08) normalizes to 50000"
);

# Open a connection to MySQL, or skip the rest of the tests.
use DSNParser;
use Sandbox;
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
SKIP: {
   skip 'Cannot connect to MySQL', 2 unless $dbh;
   my $vp = new_ok "VersionParser", [ $dbh ], "new from dbh works";
   cmp_ok($vp, "ge", '3.23.00', 'Version is > 3.23');

   unlike(
      $vp->innodb_version(),
      qr/DISABLED/,
      "InnoDB version"
   );

   my ($ver) = $dbh->selectrow_array("SELECT VERSION()");
   $ver =~ s/(\d+\.\d+\.\d+).*/$1/;

   is(
      "$vp",
      $ver,
      "object from dbh stringifies as expected"
   );

   my (undef, $flavor) = $dbh->selectrow_array("SHOW VARIABLES LIKE 'version_comment'");
   SKIP: {  
      skip "Couldn't fetch version_comment from the db", 1 unless $flavor;
      is(
         $vp->flavor(),
         $flavor,
         "When created from a dbh, flavor is set through version_comment",
      );
   };
}

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
