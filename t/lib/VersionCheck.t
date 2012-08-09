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
   diag(Dumper($versions));
   is_deeply(
      $versions,
      $args{versions},
      "$args{name} versions"
   );

   # Perl 5.8 $^V/$PERL_VERSION is borked, make sure
   # the module is coping with it.
   if ( $items->{Perl} ) {
      like(
         $versions->{Perl},
         q/\d+\.\d+.\d+/,
         "Perl version looks like a version"
      );
   }

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
      'Perl' => sprintf('%vd', $PERL_VERSION),
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

SKIP: {
   skip "Cannot cannot to sandbox master", 2 unless $dbh;

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
}

# I can't think of a way to make these 2 OS tests more specific
# since the test env doesn't know what OS its running on.  We
# at least know that an OS should have these two things: a word
# and version with at least major and minor numbers.
my $os = $vc->get_os;
diag($os);

like(
   $os,
   qr/^\w+/,
   "OS has some kind of name"
);

like(
   $os,
   qr/\d+\.\d+/,
   "OS has some kind of version"
);

# get_os() runs a lot of shell cmds that include newlines,
# but the client's response can't have newlines in the versions
# becuase newlines separate items.
ok(
   $os !~ m/\n$/,
   "Newline stripped from OS"
);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox") if $dbh;
done_testing;
exit;
