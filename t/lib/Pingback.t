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

my $response;  # responses to client
my $post;      # what client sends for POST
{
   package FakeUA;

   sub new { bless {}, $_[0] }
   sub request {
      my ($self, $type, $url, $content) = @_;
      if ( $type eq 'GET' ) {
         return shift @$response;
      }
      elsif ( $type eq 'POST' ) {
         $post = $content;
         return shift @$response;
      }
      die "Invalid client request method: $type";
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

   $response = $args{response};
   $post = "";  # clear previous test

   my $sug;
   eval {
      $sug = Pingback::pingback(
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
      $post ? ($post->{content} || '') : '',
      $args{post},
      "$args{name} client response"
   );

   is_deeply(
      $sug,
      $args{sug},
      "$args{name} suggestions"
   );
}

test_pingback(
   name => "Perl version and module version",
   response => [
      # in response to client's GET
      { status  => 200,
        content => "Perl;perl_version;PERL_VERSION\nData::Dumper;perl_module_version\n",
      },
      # in response to client's POST
      { status  => 200,
        content => "Perl;perl_version;Perl 5.8 is wonderful.\nData::Dumper;perl_module_version;Data::Printer is nicer.\n",
      }
   ],
   # client should POST this
   post => "Data::Dumper;perl_module_version;$dd_ver\nPerl;perl_version;$perl_ver\n",
   # Server should return these suggetions after the client posts
   sug  => [
      'Data::Printer is nicer.',
      'Perl 5.8 is wonderful.',
   ],
);

# Client should handle not getting any suggestions.

test_pingback(
   name => "Versions but no suggestions",
   response => [
      # in response to client's GET
      { status  => 200,
        content => "Perl;perl_version;PERL_VERSION\nData::Dumper;perl_module_version\n",
      },
      # in response to client's POST
      { status  => 200,
        content => "",
      }
   ],
   post => "Data::Dumper;perl_module_version;$dd_ver\nPerl;perl_version;$perl_ver\n",
   sug  => undef,
);

# Client should handle no response to GET.

test_pingback(
   name => "No response to GET",
   response => [],
   post => "",
   sug  => undef,
);

# Client should handle no response to POST.

test_pingback(
   name => "No response to POST",
   response => [
      # in response to client's GET
      { status  => 200,
        content => "Perl;perl_version;PERL_VERSION\nData::Dumper;perl_module_version\n",
      },
   ],
   post => "Data::Dumper;perl_module_version;$dd_ver\nPerl;perl_version;$perl_ver\n",
   sug  => undef,
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
      dbh  => $dbh,
      response => [
         # in response to client's GET
         { status  => 200,
           content => "MySQL;mysql_variable;version,version_comment\n",
         },
         # in response to client's POST
         { status  => 200,
           content => "MySQL;mysql_variable;Percona Server is fast.\n",
         }
      ],
      # client should POST this
      post => "MySQL;mysql_variable;$mysql_ver $mysql_distro\n",
      # Server should return these suggetions after the client posts
      sug => ['Percona Server is fast.'],
   );
}

# #############################################################################
# Testing time_to_check
# #############################################################################

my $dir   = File::Spec->tmpdir();
my $file  = File::Spec->catfile($dir, 'percona-toolkit-version-check-test');

unlink $file;

ok(
   Pingback::time_to_check($file),
   "time_to_check() returns true if the file doesn't exist",
);

ok(
   !Pingback::time_to_check($file),
   "...but false if it exists and it's been less than 24 hours",
);

my $one_day = 60 * 60 * 24;
my ($old_atime, $old_mtime) = (stat($file))[8,9];

utime($old_atime - $one_day * 2, $old_mtime - $one_day * 2, $file);

cmp_ok(
   (stat($file))[9],
   q{<},
   time() - $one_day,
   "Sanity check, the file's mtime is now at least one day behind time()",
);

ok(
   Pingback::time_to_check($file),
   "time_to_check returns true if the file exists and it's mtime is at least one day old",
);

ok(
   !Pingback::time_to_check($file),
   "...but fails if tried a second time, as the mtime has been updated",
);

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox")
   if $dbh;
done_testing;
exit;
