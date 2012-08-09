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

use Pingback;
use PerconaTest;
use DSNParser;
use Sandbox;
my $dp  = DSNParser->new(opts=>$dsn_opts);
my $sb  = Sandbox->new(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

# #############################################################################
# Fake User Agent package, so we can simulate server responses
# and fake accepting client responses.
# #############################################################################

my $get;   # server reponses
my $post;  # client responses
{
   package FakeUA;

   sub new { bless {}, $_[0] }
   sub request {
      my ($self, $type, $url, $content) = @_;
      return shift @$get if $type eq 'GET';
      $post = $content   if $type eq 'POST';
      return;
   }
}

my $fake_ua = FakeUA->new();

# #############################################################################
# Pingback tests
# #############################################################################

my $url      = 'http://upgrade.percona.com';
my $perl_ver = sprintf '%vd', $PERL_VERSION;
my $dd_ver   = $Data::Dumper::VERSION;

sub test_pingback {
   my (%args) = @_;

   $get  = $args{get};
   $post = "";  # clear previous test

   eval {
      Pingback::pingback(
         url => $url,
         dbh => $args{dbh},
         ua  => $fake_ua,
      );
   };
   is(
      $EVAL_ERROR,
      "",
      "$args{name} no error"
   );

   is(
      $post,
      $args{post},
      "$args{name} client response"
   )
}

test_pingback(
   name => "Perl version and Data::Dumper::VERSION",
   # Client gets this from the server:
   get  => [
      { status  => 200,
        content => "Perl;perl_variable;PERL_VERSION\nData::Dumper;perl_variable\n",
      },
   ],
   # And it responds with this:
   post => "Data::Dumper;perl_variable;$dd_ver\nPerl;perl_variable;$perl_ver\n",
);

# #############################################################################
# MySQL version
# #############################################################################
SKIP: {
   skip 'Cannot connect to sandbox master', 2 unless $dbh;

   my (undef, $mysql_ver)
      = $dbh->selectrow_array("SHOW VARIABLES LIKE 'version'");
   my (undef, $mysql_distro)
      = $dbh->selectrow_array("SHOW VARIABLES LIKE 'version_comment'");

   test_pingback(
      name => "MySQL version",
      get  => [
         { status  => 200,
           content => "MySQL;mysql_variable;version,version_comment\n",
         },
      ],
      post => "MySQL;mysql_variable;$mysql_ver $mysql_distro\n",
      dbh  => $dbh,
   );
}

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox")
   if $dbh;
done_testing;
exit;
