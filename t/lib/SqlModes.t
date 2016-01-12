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

use DSNParser;
use Sandbox;
use PerconaTest;

use SqlModes;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}
else {
   plan tests => 4;
}


my $sm = new SqlModes($dbh);

# first we set a known mode to make sure it's there

$sm->add('NO_AUTO_CREATE_USER');

# #############################################################################
# test has_mode
# #############################################################################

ok (
   $sm->has_mode('NO_AUTO_CREATE_USER'),
   "has_mode works",
);

# #############################################################################
# test get_modes 
# #############################################################################

my $modes = $sm->get_modes();

ok (
   $modes->{'NO_AUTO_CREATE_USER'} == 1,
   "get_modes works",
);

# #############################################################################
# test del()  
# #############################################################################

$sm->del('NO_AUTO_CREATE_USER');

ok (
   !$sm->has_mode('NO_AUTO_CREATE_USER'),
   "del works",
);



# #############################################################################
# test add()  
# #############################################################################

$sm->add('NO_AUTO_CREATE_USER');

ok (
   $sm->has_mode('NO_AUTO_CREATE_USER'),
   "add works",
);

# #############################################################################
# DONE
# #############################################################################

#$sb->wipe_clean($dbh);
#ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
