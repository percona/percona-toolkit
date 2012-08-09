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

use PerconaTest;

use Pingback;

my @requests;
{
   package FakeUA;

   sub new { bless $_[1], $_[0] }
   sub request {
      my ($self, $type, $url, $content) = @_;

      if ( $type ne 'GET' ) {
         push @requests, $content;
      }
      return shift @{ $self };
   }
}

my $fake_ua = FakeUA->new([
   { status => 200, content => "Perl;perl_variable;PERL_VERSION\nData::Dumper;perl_variable\n" }, # GET 1
   { status => 200, }, # POST 1
   { status => 200, content => "Perl;perl_variable;PERL_VERSION\nMySQL;mysql_variable;version_comment,version\n", }, # GET 2
   { status => 200, }, # POST 2
]);

@requests = ();
Pingback::pingback('http://www.percona.com/fake_url', undef, $fake_ua);

is(
   scalar @requests,
   1,
   "..and it sends one request"
);

my $v = sprintf('Perl,%vd', $^V);
like(
   $requests[0]->{content},
   qr/\Q$v/,
   "..which has the expected version of Perl"
);

like(
   $requests[0]->{content},
   qr/\Q$Data::Dumper::VERSION/,
   "..and the expected D::D version"
);

#@requests = ();
#my ($out) = full_output( sub { Pingback::pingback('http://www.percona.com/fake_url', undef, $fake_ua) } );
# 

use DSNParser;
use Sandbox;
my $dp  = DSNParser->new(opts=>$dsn_opts);
my $sb  = Sandbox->new(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
SKIP: {
   skip 'Cannot connect to sandbox master', 3 unless $dbh;

   my (undef, $mysql_version)
      = $dbh->selectrow_array("SHOW VARIABLES LIKE 'version'");
   my (undef, $mysql_version_comment)
      = $dbh->selectrow_array("SHOW VARIABLES LIKE 'version_comment'");
      
   @requests = ();
   Pingback::pingback('http://www.percona.com/fake_url', $dbh, $fake_ua);

   like(
      $requests[0]->{content},
      qr/\Q$v/,
      "Second request has the expected version of Perl"
   );

   like(
      $requests[0]->{content},
      qr/\Q$mysql_version_comment $mysql_version/,
      "..and gets the MySQL version"
   );
}

done_testing;
