#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use File::Temp qw(tempdir);

use Percona::Test;
use Sandbox;
use Percona::Test::Mock::UserAgent;
require "$trunk/bin/pt-agent";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
my $dsn = $sb->dsn_for('master');
my $o   = new OptionParser();
$o->get_specs("$trunk/bin/pt-agent");
$o->get_opts();
my $cxn = Cxn->new(
   dsn_string   => $dsn,
   OptionParser => $o,
   DSNParser    => $dp,
);

Percona::Toolkit->import(qw(Dumper));
Percona::WebAPI::Representation->import(qw(as_hashref));

# Running the agent is going to cause it to schedule the services,
# i.e. write a real crontab.  The test box/user shouldn't have a
# crontab, so we'll warn and clobber it if there is one.
my $crontab = `crontab -l 2>/dev/null`;
if ( $crontab ) {
   warn "Removing crontab: $crontab\n";
   `crontab -r`;
}

my $tmp_lib = "/tmp/pt-agent";
my $tmp_log = "/tmp/pt-agent.log";
my $tmp_pid = "/tmp/pt-agent.pid";

diag(`rm -rf $tmp_lib`) if -d $tmp_lib;
unlink $tmp_log if -f $tmp_log;
unlink $tmp_pid if -f $tmp_pid;

my $config_file = pt_agent::get_config_file();
unlink $config_file if -f $config_file;

my $output;

{
   no strict;
   no warnings;
   local *pt_agent::start_agent = sub {
      print "start_agent\n";
      return {
         agent  => 0,
         client => 0,
         daemon => 0,
      };
   };
   local *pt_agent::run_agent   = sub {
      print "run_agent\n";
   };

   $output = output(
      sub {  
         pt_agent::main(
            qw(--api-key 123)
         );
      },
      stderr => 1,
   );
}

like(
   $output,
   qr/start_agent\nrun_agent\n/,
   "Starts and runs without a config file"
);

# #############################################################################
# Done.
# #############################################################################

`crontab -r 2>/dev/null`;

if ( -f $config_file ) {
   unlink $config_file 
      or warn "Error removing $config_file: $OS_ERROR";
}

done_testing;
