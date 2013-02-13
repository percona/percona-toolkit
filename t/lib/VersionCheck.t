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
use Digest::MD5 qw(md5_hex);
use Sys::Hostname qw(hostname);

use VersionCheck;
use DSNParser;
use Sandbox;
use PerconaTest;
use Percona::Toolkit;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');

my $vc = 'VersionCheck';

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
   local $ENV{PATH} = File::Spec->catfile($ENV{PERCONA_TOOLKIT_BRANCH}, "bin") . ":$ENV{PATH}";
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
         'pt-archiver' => $Percona::Toolkit::VERSION,
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
# Former Pingback tests
# #############################################################################

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

   (undef, $master_id) = VersionCheck::_generate_identifier(
      { dbh => $master_dbh, dsn => { h => '127.1', P => 12345 }});
   (undef, $slave1_id) = VersionCheck::_generate_identifier(
      { dbh => $slave1_dbh, dsn => { h => '127.1', P => 12346 }});

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

# Fake User Agent package, so we can simulate server responses
# and fake accepting client responses.
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
         $sug = VersionCheck::pingback(
            url       => $url,
            instances => $args{instances},
            ua        => $fake_ua,
         );
      };
   }
   else {
      eval {
         $sug = VersionCheck::pingback(
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

   my $expect_post;
   if ( $args{post} ) {
      $expect_post = join("\n",
         map { "$_->{id};$_->{item};$_->{val}" }
         sort {
         $a->{item} cmp $b->{item} ||
         $a->{id}   cmp $b->{id}
      } @{$args{post}});
      $expect_post .= "\n";
   }
   is(
      $post ? ($post->{content} || '') : '',
      $expect_post || '',
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
   post => [
      {
         item => 'Data::Dumper',
         id   => $general_id,
         val  => $dd_ver,
      },
      {
         item => 'Perl',
         id   => $general_id,
         val  => $perl_ver,
      },
   ],
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
   post => [
      {
         item => 'Data::Dumper',
         id   => $general_id,
         val  => $dd_ver,
      },
      {
         item => 'Perl',
         id   => $general_id,
         val  => $perl_ver,
      },
   ],
   sug  => undef,
);

# Client should handle no response to GET.

test_pingback(
   name => "No response to GET",
   response => [],
   no_response => 1,
   post => undef,
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
   post => [
      {
         id   => $general_id,
         item => 'Data::Dumper',
         val  => $dd_ver,
      },
      {
         id   => $general_id,
         item => 'Perl',
         val  => $perl_ver,
      },
   ],
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
      post => [
         {
            id   => $master_id,
            item => 'MySQL',
            val  => "$mysql_ver $mysql_distro",
         }
      ],
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

my $time = int(time());

ok(
   VersionCheck::time_to_check($file, [], $time),
   "time_to_check returns true if the file doesn't exist",
);

ok(
   !-f $file,
   "time_to_check doesn't create the checks file"   
);

VersionCheck::update_checks_file($file, [], $time);

ok(
   -f $file,
   "update_checks_file creates the checks file"
);

ok(
   !VersionCheck::time_to_check($file, [], $time),
   "time_to_check is false if file exists and it's been less than 24 hours"
);

my $one_day = 60 * 60 * 24;
my ($orig_atime, $orig_mtime) = (stat($file))[8,9];

my $mod_atime = $orig_atime - $one_day * 2;
my $mod_mtime = $orig_mtime - $one_day * 2;

utime($mod_atime, $mod_mtime, $file);

cmp_ok(
   (stat($file))[9],
   q{<},
   time() - $one_day,
   "The file's mtime is at least one day behind time()",
);

ok(
   VersionCheck::time_to_check($file, [], $time),
   "time_to_check true if file exists and mtime < one day"
);

my ($atime, $mtime) = (stat($file))[8,9];

is($mod_atime, $atime, "time_to_check doesn't update the atime");
is($mod_mtime, $mtime, "time_to_check doesn't update the mtime");

VersionCheck::update_checks_file($file, [], $time);

($atime, $mtime) = (stat($file))[8,9];

ok(
      $orig_atime == $atime
   && $orig_mtime == $mtime,
   "...but update_checks_file does"
);

ok(
   !VersionCheck::time_to_check($file, [], $time),
   "...and time_to_check fails after update_checks_file"
);

# #############################################################################
# _generate_identifier
# #############################################################################

is(
   VersionCheck::_generate_identifier( { dbh => undef, dsn => { h => "localhost", P => 12345 } } ),
   md5_hex("localhost", 12345),
   "_generate_identifier() works as expected for 4.1",
);

SKIP: {
   skip 'Cannot connect to sandbox master', 2 unless $master_dbh;

   my $expect_master_id;
   if ( $sandbox_version ge '5.1' ) {
      my $sql           = q{SELECT CONCAT(@@hostname, @@port)};
      my ($name)        = $master_dbh->selectrow_array($sql);
      $expect_master_id = md5_hex($name);
   }
   elsif ( $sandbox_version eq '5.0' ) {
      my $sql           = q{SELECT @@hostname};
      my ($hostname)    = $master_dbh->selectrow_array($sql);
      $sql              = q{SHOW VARIABLES LIKE 'port'};
      my (undef, $port) = $master_dbh->selectrow_array($sql);
      $expect_master_id = md5_hex($hostname . $port);
   }
   else {
      $expect_master_id = md5_hex("localhost", 12345);
   }
   
   is(
      $master_id,
      $expect_master_id,
      "_generate_identifier() for MySQL $sandbox_version"
   );

   # The time limit file already exists (see previous tests), but this is
   # a new MySQL instance, so it should be time to check it.
   my ($is_time, $check_inst) = VersionCheck::time_to_check(
      $file,
      [ $master_inst ],
   );
   VersionCheck::update_checks_file($file, $check_inst, int(time()));
   
   ok(
      $is_time,
      "Time to check a new MySQL instance ID",
   );

   is_deeply(
      $check_inst,
      [ $master_inst ],
      "Check just the new instance"
   );

   
   ($is_time, $check_inst) = VersionCheck::time_to_check(
      $file,
      [ $master_inst ],
   );

   VersionCheck::update_checks_file($file, $check_inst, int(time()));
   
   ok(
      !$is_time,
      "...but not the second time around",
   );

   open my $fh, q{>}, $file or die $!;
   print { $fh } "$master_id," . (time() - $one_day * 2) . "\n";
   close $fh;

   ($is_time, $check_inst) = VersionCheck::time_to_check(
      $file,
      [ $master_inst ],
   );

   VersionCheck::update_checks_file($file, $check_inst, int(time()));
   
   is_deeply(
      $check_inst,
      [ $master_inst ],
      "...unless more than a day has gone past",
   );

   ($is_time, $check_inst) = VersionCheck::time_to_check(
      $file,
      [ $master_inst, $slave1_inst ],
   );

   VersionCheck::update_checks_file($file, $check_inst, int(time()));
   
   is_deeply(
      $check_inst,
      [ $slave1_inst ],
      "With multiple ids, time_to_check() returns only those that need checking",
   );

   ok(
      $is_time,
      "...and is time to check"
   );

   ($is_time, $check_inst) = VersionCheck::time_to_check(
      $file,
      [ $master_inst, $slave1_inst ],
   );

   VersionCheck::update_checks_file($file, $check_inst, int(time()));
   
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
      post => [
         {
            id   => $slave1_id,
            item => 'MySQL',
            val  => "$mysql_ver $mysql_distro",
         },
         {
            id   => $master_id,
            item => 'MySQL',
            val  => "$mysql_ver $mysql_distro",
         }
      ],
      # Server should return these suggetions after the client posts
      sug => [
         'Percona Server is fast.',
         'Percona Server is fast.',
      ], 
   );
}

# #############################################################################
# Check that the --v-c OPT validation works everywhere
# #############################################################################

use File::Basename qw(basename);

my @vc_tools = grep { chomp; basename($_) =~ /\A[a-z-]+\z/ }
              `grep --files-with-matches VersionCheck $trunk/bin/*`;

foreach my $tool ( @vc_tools ) {
   my $tool_name = basename($tool);
   my $output = `$tool --version-check ftp`;
   like(
      $output,
      qr/\Q* --version-check invalid value ftp.  Accepted values are https, http, auto and off/,
      "$tool_name validates --version-check"
   );
}

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox")
   if $master_dbh;
done_testing;
