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

local $ENV{PERCONA_FORCE_VERSION_CHECK} = 1;

sub test_v {
   my (%args) = @_;

   my $items = VersionCheck::parse_server_response(
      response => $args{response},
   );
   is_deeply(
      $items,
      $args{items},
      "$args{name} items"
   );

   my $versions = VersionCheck::get_versions(
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

# #############################################################################
# Version getters
# #############################################################################

# I can't think of a way to make these 2 OS tests more specific
# since the test env doesn't know what OS its running on.  We
# at least know that an OS should have these two things: a word
# and version with at least major and minor numbers.
my $os = VersionCheck::get_os_version();

like(
   $os,
   qr/^\w+/,
   "OS has some kind of name"
);

SKIP: {
    skip "Skipping since for example ubuntu return something like 'Ubuntu yakkety Yak'",0;
    like(
       $os,
       qr/\d+\.\d+/,
       "OS has some kind of version"
    );
}

# get_os() runs a lot of shell cmds that include newlines,
# but the client's response can't have newlines in the versions
# becuase newlines separate items.
ok(
   $os !~ m/\n$/,
   "Newline stripped from OS"
);

is(
   VersionCheck::get_perl_module_version(
      item => {
         item => 'DBD::mysql',
         type => 'perl_module_version',
         vars => [],
      },
      instances => [],
   ),
   $DBD::mysql::VERSION,
   "get_perl_module_version(): DBD::mysql"
);

# #############################################################################
# Validate items
# #############################################################################
   
my $versions = VersionCheck::get_versions(
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

   (undef, $master_id) = VersionCheck::get_instance_id(
      { dbh => $master_dbh, dsn => { h => '127.1', P => 12345 }});
   (undef, $slave1_id) = VersionCheck::get_instance_id(
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
            instances => $args{instances} || [],
            ua        => $fake_ua,
         );
      };
   }
   else {
      eval {
         $sug = VersionCheck::pingback(
            url       => $url,
            instances => $args{instances} || [],
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
# get_instances_to_check()
# #############################################################################

my $vc_file = VersionCheck::version_check_file();
unlink $vc_file if -f $vc_file;
PerconaTest::wait_until( sub { !-f $vc_file } );

my $now = 100000;  # a fake Unix ts works

my $instances = [];

sub get_check {
   my (%args) = @_;
   return VersionCheck::get_instances_to_check(
      instances => $instances,
      vc_file   => $vc_file,
      now       => $args{now} || $now,
   );
}

my $check = get_check();

is_deeply(
   $check,
   [],
   "get_instances_to_check(): no instances"
) or diag(Dumper($check));

ok(
   !-f $vc_file,
   "Version check file not created"
);

# Add default system instance.  version_check() does this.
push @$instances, { id => 0, name => "system" };

eval {
   VersionCheck::update_check_times(
      instances => $instances,
      vc_file   => $vc_file,
      now       => $now,
   );
};

is(
   $EVAL_ERROR,
   "",
   "update_check_times(): no error"
);

ok(
   -f $vc_file,
   "update_check_times() created version check file"
);

my $output = `cat $vc_file`;

is(
   $output,
   "0,$now\n",
   "Version check file contents"
);

$check = get_check();

is_deeply(
   $check,
   [],
   "get_instances_to_check(): no instances to check"
) or diag(Dumper($check));

my $check_time_limit = VersionCheck::version_check_time_limit();

open my $fh, '>', $vc_file
   or die "Cannot write to $vc_file: $OS_ERROR";
print { $fh } "0,$now\n";
close $fh;

# You can verify this test by adding - 1 to this line,
# making it seem like the instance hasn't been checked
# in 1 second less than the limit.
$check = get_check(now => $now + $check_time_limit);

is_deeply(
   $check,
   $instances,
   "get_instances_to_check(): time to check instance"
) or diag(Dumper($check));

# #############################################################################
# get_instance_id
# #############################################################################

is(
   VersionCheck::get_instance_id(
      { dbh => undef, dsn => { h => "localhost", P => 12345 } } ),
   md5_hex("localhost", 12345),
   "get_instance_id() works as expected for 4.1",
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
      "get_instance_id() for MySQL $sandbox_version"
   );

   # The time limit file already exists (see previous tests), but this is
   # a new MySQL instance, so it should be time to check it.
   push @$instances, $master_inst;
   $check = get_check();

   is_deeply(
      $check,
      [ $master_inst ],
      "get_instances_to_check(): check new MySQL instance"
   ) or diag(Dumper($check));

   # Write vc file as if the system was checked now, but the MySQL
   # instance was checked 10 hours ago.  So it won't need to checked
   # for another 14 hours.
   my $ten_hours      = 60 * 60 * 10;
   my $fourteen_hours = 60 * 60 * 14;
   open my $fh, '>', $vc_file or die "Cannot write to $vc_file: $OS_ERROR";
   print { $fh } "0,$now\n$master_id," . ($now - $ten_hours) . "\n";
   close $fh;

   $check = get_check();

   is_deeply(
      $check,
      [],
      "get_instances_to_check(): not time to check either instance"
   ) or diag(Dumper($check));

   # Pretend like those 14 hours have passed now.
   $check = get_check(now => $now + $fourteen_hours);

   is_deeply(
      $check,
      [ $master_inst ],
      "get_instances_to_check(): time to check one of two instances"
   ) or diag(Dumper($check));
}

# ############################################################################
# Make sure the MySQL version checks happen for all instances
# if the file doesn't exist.
# #############################################################################

unlink $vc_file if -f $vc_file;
PerconaTest::wait_until( sub { !-f $vc_file } );

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
   next if $tool_name eq 'pt-agent';
   my $output = `$tool --help`;
   like(
      $output,
      qr/^#?\s+--\[no\]version-check/m,
      "--version-check is on in $tool_name"
   );
}

# #############################################################################
# Done.
# #############################################################################
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox")
   if $master_dbh;
done_testing;
