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
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');

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
      items     => $items,
      instances => [
         {
            id   => "0xDEADBEEF",
            name => "master",
            dbh  => $master_dbh,
         },
         {
            id   => "0x8BADF00D",
            name => "slave1",
            dbh  => $slave1_dbh,
         },
      ],
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
         qr/\d+\.\d+.\d+/,
         "Perl version looks like a version"
      );
   }

   return;
}

test_v(
   name     => "Perl version",
   response => "Perl;perl_version\n",
   items    => {
      'Perl' => {
         item => 'Perl',
         type => 'perl_version',
         vars => [],
      },
   },
   versions => {
      'Perl' => sprintf('%vd', $PERL_VERSION),
   },
);

test_v(
   name     => "perl_module_version",
   response => "Data::Dumper;perl_module_version\n",
   items    => {
      'Data::Dumper' => {
         item => 'Data::Dumper',
         type => 'perl_module_version',
         vars => [],
      },
   },
   versions => {
      'Data::Dumper' => $Data::Dumper::VERSION,
   },
);

test_v(
   name     => "bin_version",
   response => "perl;bin_version\n",
   items    => {
      'perl' => {
         item => 'perl',
         type => 'bin_version',
         vars => [],
      },
   },
   versions => {
      'perl' => sprintf('%vd', $PERL_VERSION),
   },
);

use File::Spec;
{
   local $ENV{PATH} = "$ENV{PATH}:" . File::Spec->catfile($ENV{PERCONA_TOOLKIT_BRANCH}, "bin");
   test_v(
      name     => "bin_version",
      response => "pt-archiver;bin_version\n",
      items    => {
         'pt-archiver' => {
            item => 'pt-archiver',
            type => 'bin_version',
            vars => [],
         },
      },
      versions => {
         'pt-archiver' => $Sandbox::Percona::Toolkit::VERSION,
      },
   );
}

SKIP: {
   skip "Cannot cannot to sandbox master", 2 unless $master_dbh;

   my (undef, $mysql_version)
      = $master_dbh->selectrow_array("SHOW VARIABLES LIKE 'version'");
   my (undef, $mysql_distro)
      = $master_dbh->selectrow_array("SHOW VARIABLES LIKE 'version_comment'");

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
         'MySQL' => {
            "0xDEADBEEF" => "$mysql_distro $mysql_version",
            "0x8BADF00D" => "$mysql_distro $mysql_version"
         },
      },
   );
}

# I can't think of a way to make these 2 OS tests more specific
# since the test env doesn't know what OS its running on.  We
# at least know that an OS should have these two things: a word
# and version with at least major and minor numbers.
my $os = $vc->get_os_version;
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
# Validate items
# #############################################################################
   
my $versions = $vc->get_versions(
   items => {
      'Foo' => {
         item => 'Foo',
         type => 'perl_variable',
         vars => [],
      },
   },
);

is_deeply(
   $versions,
   {},
   "perl_variable is not a valid type"
);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox")
   if $master_dbh;
done_testing;
exit;
