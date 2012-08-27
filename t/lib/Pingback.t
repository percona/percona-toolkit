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

use Digest::MD5 qw(md5_hex);
use Sys::Hostname  qw(hostname);

my $dp  = DSNParser->new(opts=>$dsn_opts);
my $sb  = Sandbox->new(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');

my $general_id = md5_hex( hostname() );
my $master_id;  # the instance ID, _not_ 12345 etc.
my $slave1_id;  # the instance ID, _not_ 12346 etc.
my ($mysql_ver, $mysql_distro);
my ($master_inst, $slave1_inst);
if ( $master_dbh ) {
   (undef, $mysql_ver)
      = $master_dbh->selectrow_array("SHOW VARIABLES LIKE 'version'");
   (undef, $mysql_distro)
      = $master_dbh->selectrow_array("SHOW VARIABLES LIKE 'version_comment'");

   my $sql    = q{SELECT CONCAT(@@hostname, @@port)};
   my ($name) = $master_dbh->selectrow_array($sql);
   $master_id = md5_hex($name);

   (undef, $slave1_id) = Pingback::_generate_identifier( { dbh => $slave1_dbh } );

   $master_inst = {
      id   => $master_id,
      name => "master",
      dbh  => $master_dbh,
   };
   $slave1_inst = {
      id   => $slave1_id,
      name => "slave1",
      dbh  => $slave1_dbh,
   };
}

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

my $url      = 'http://staging.upgrade.percona.com';
my $perl_ver = sprintf '%vd', $PERL_VERSION;
my $dd_ver   = $Data::Dumper::VERSION;

sub test_pingback {
   my (%args) = @_;

   $response = $args{response};
   $post = "";  # clear previous test

   my $sug;
   if ( $args{version_check} ) {
      eval {
         $sug = Pingback::pingback(
            url       => $url,
            instances => $args{instances},
            ua        => $fake_ua,
         );
      };
   }
   else {
      eval {
         $sug = Pingback::pingback(
            url       => $url,
            instances => $args{instances},
            ua        => $fake_ua,
         );
      };
   }
   if ( $args{no_response} ) {
      like(
         $EVAL_ERROR,
         qr/No response/,
         "$args{name} dies with \"no response\" error"
      );
   }
   else {
      is(
         $EVAL_ERROR,
         "",
         "$args{name} no error"
      );
   }

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
   post => "$general_id;Data::Dumper;$dd_ver\n$general_id;Perl;$perl_ver\n",
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
   post => "$general_id;Data::Dumper;$dd_ver\n$general_id;Perl;$perl_ver\n",
   sug  => undef,
);

# Client should handle no response to GET.

test_pingback(
   name => "No response to GET",
   response => [],
   no_response => 1,
   post => "",
   sug  => undef,
);

# Client should handle no response to POST.

test_pingback(
   name => "No response to POST",
   no_response => 1,
   response => [
      # in response to client's GET
      { status  => 200,
        content => "Perl;perl_version;PERL_VERSION\nData::Dumper;perl_module_version\n",
      },
   ],
   post => "$general_id;Data::Dumper;$dd_ver\n$general_id;Perl;$perl_ver\n",
   sug  => undef,
);

# #############################################################################
# MySQL version
# #############################################################################
SKIP: {
   skip 'Cannot connect to sandbox master', 2 unless $master_dbh;
 
   test_pingback(
      name => "MySQL version",
      instances => [ $master_inst ],
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
      post => "$master_id;MySQL;$mysql_ver $mysql_distro\n",
      # Server should return these suggetions after the client posts
      sug => ['Percona Server is fast.'],
   );
}

# #############################################################################
# Testing time_to_check
# #############################################################################

my $dir   = File::Spec->tmpdir();
my $file  = File::Spec->catfile($dir, 'percona-toolkit-version-check-test');

unlink $file if -f $file;

ok(
   Pingback::time_to_check($file, []),
   "time_to_check() returns true if the file doesn't exist",
);

ok(
   !Pingback::time_to_check($file, []),
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
   Pingback::time_to_check($file, []),
   "time_to_check true if file exists and mtime < one day", #>"
);

ok(
   !Pingback::time_to_check($file, []),
   "...but fails if tried a second time, as the mtime has been updated",
);

# #############################################################################
# _generate_identifier
# #############################################################################

is(
   Pingback::_generate_identifier( { dbh => undef, dsn => { h => "localhost", P => 12345 } } ),
   md5_hex("localhost", 12345),
   "_generate_identifier() works as expected for 4.1",
);

SKIP: {
   skip 'Cannot connect to sandbox master', 2 unless $master_dbh;
   skip 'Requires MySQL 5.0.38 or newer', unless $sandbox_version ge '5.0.38';

   is(
      Pingback::_generate_identifier( { dbh => $master_dbh, dsn => undef } ),
      $master_id,
      "_generate_identifier() works with a dbh"
   );

   # The time limit file already exists (see previous tests), but this is
   # a new MySQL instance, so it should be time to check it.
   my ($is_time, $check_inst) = Pingback::time_to_check(
      $file,
      [ $master_inst ],
   );

   ok(
      $is_time,
      "Time to check a new MySQL instance ID",
   );

   is_deeply(
      $check_inst,
      [ $master_inst ],
      "Check just the new instance"
   );

   
   ($is_time, $check_inst) = Pingback::time_to_check(
      $file,
      [ $master_inst ],
   );

   ok(
      !$is_time,
      "...but not the second time around",
   );

   open my $fh, q{>}, $file or die $!;
   print { $fh } "$master_id," . (time() - $one_day * 2) . "\n";
   close $fh;

   ($is_time, $check_inst) = Pingback::time_to_check(
      $file,
      [ $master_inst ],
   );

   is_deeply(
      $check_inst,
      [ $master_inst ],
      "...unless more than a day has gone past",
   );

   ($is_time, $check_inst) = Pingback::time_to_check(
      $file,
      [ $master_inst, $slave1_inst ],
   );

   is_deeply(
      $check_inst,
      [ $slave1_inst ],
      "With multiple ids, time_to_check() returns only those that need checking",
   );

   ok(
      $is_time,
      "...and is time to check"
   );

   ($is_time, $check_inst) = Pingback::time_to_check(
      $file,
      [ $master_inst, $slave1_inst ],
   );

   ok(
      !$is_time,
      "...and false if there isn't anything to check",
   );
}

# ############################################################################
# Make sure the MySQL version checks happen for all instances
# if the file doesn't exist.
# #############################################################################

unlink $file if -f $file;
PerconaTest::wait_until( sub { !-f $file } );

SKIP: {
   skip 'Cannot connect to sandbox master', 2 unless $master_dbh;

   test_pingback(
      name => "Create file and get MySQL versions",
      version_check => 1,
      instances => [ $master_inst, $slave1_inst ],
      response => [
         # in response to client's GET
         { status  => 200,
           content => "MySQL;mysql_variable;version,version_comment\n",
         },
         # in response to client's POST
         { status  => 200,
           content => "$master_id;MySQL;Percona Server is fast.\n$slave1_id;MySQL;Percona Server is fast.\n",
         }
      ],
      # client should POST this
      post => "$master_id;MySQL;$mysql_ver $mysql_distro\n$slave1_id;MySQL;$mysql_ver $mysql_distro\n",
      # Server should return these suggetions after the client posts
      sug => [
         'Percona Server is fast.',
         'Percona Server is fast.',
      ], 
   );
}

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh) if $master_dbh;
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox")
   if $master_dbh;
done_testing;
exit;
