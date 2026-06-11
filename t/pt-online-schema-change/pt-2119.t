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

use Data::Dumper;
use PerconaTest;
use Sandbox;

require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $source_dbh = $sb->get_dbh_for('source');

if ( !$source_dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

my $vp = VersionParser->new($source_dbh);

if ( $vp->cmp('8.0.14') < 0 || $vp->cmp('8.0.17') >= 0 || $vp->flavor() =~ m/maria/i ) {
   plan skip_all => 'Test requires versions between 8.0.14 and 8.0.17';
}

# The sandbox servers run with lock_wait_timeout=3 and it's not dynamic
# so we need to specify --set-vars innodb_lock_wait_timeout=3 else the
# tool will die.
my $source_dsn = 'h=127.1,P=12345,u=msandbox,p=msandbox';
my @args       = (qw(--set-vars innodb_lock_wait_timeout=3));
my $sample     = "t/pt-online-schema-change/samples/";
my $plugin     = "$trunk/$sample/plugins";
my $output;
my $exit_status;

$sb->load_file('source', "$sample/pt-2119.sql");

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=pt_osc,t=t",
      "--alter", "ENGINE=InnoDB",
      '--execute') },
);

is(
   $exit_status,
   0,
   "No error for table without FK reference"
);

like(
   $output,
   qr/Successfully altered `pt_osc`.`t`/s,
   'Table successfully altered'
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=pt_osc,t=person",
      "--alter", "ENGINE=InnoDB",
      '--execute') },
);

is(
   $exit_status,
   3,
   "Error for the parent table"
);

like(
   $output,
   qr/There is an error in MySQL that makes the server to die when trying to rename a table with FKs./s,
   'Parent table was not altered'
);

($output, $exit_status) = full_output(
   sub { pt_online_schema_change::main(@args,
      "$source_dsn,D=pt_osc,t=test_table",
      "--alter", "ENGINE=InnoDB",
      '--execute') },
);

is(
   $exit_status,
   3,
   "Error for the child table"
);

like(
   $output,
   qr/There is an error in MySQL that makes the server to die when trying to rename a table with FKs./s,
   'Child table was not altered'
);
# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($source_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
