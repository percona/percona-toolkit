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

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-duplicate-key-checker";

require VersionParser;
my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('source');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox source';
}

my $cnf    = "/tmp/12345/my.sandbox.cnf";
my $sample = "t/pt-duplicate-key-checker/samples/";
my @args   = ('-F', $cnf, qw(-h 127.1));

$sb->wipe_clean($dbh);
$sb->create_dbs($dbh, ['test']);

my $transform_int = undef;
# In version 8.0 integer display width is deprecated and not shown in the outputs.
# So we need to transform our samples.
if ($sandbox_version ge '8.0') {
   $transform_int = sub {
      my $txt = slurp_file(shift);
      $txt =~ s/int\(\d{1,2}\)/int/g;
      print $txt;
   };
}

# #############################################################################
# Issue 295: Enhance rules for clustered keys in mk-duplicate-key-checker
# #############################################################################
$sb->load_file('source', 't/pt-duplicate-key-checker/samples/issue_295.sql', 'test');
ok(
   no_diff(
      sub { pt_duplicate_key_checker::main(@args, qw(-d issue_295)) },
      ($sandbox_version ge '5.1' ? "$sample/issue_295-51.txt"
                                 : "$sample/issue_295.txt"),
      transform_sample => $transform_int
   ),
   "Shorten, not remove, clustered dupes - InnoDB"
) or diag($test_diff);

SKIP: {
   skip "This test requires TokuDB", 1 if ( !$sb->has_engine('source', 'TokuDB') ) ;

   $dbh->do('SET binlog_format="ROW"');
   $dbh->do('ALTER TABLE issue_295.t ENGINE=TokuDB');

   ok(
      no_diff(
         sub { pt_duplicate_key_checker::main(@args, qw(-d issue_295)) },
         "$sample/issue_295-51.txt",
         transform_sample => $transform_int
      ),
      "Shorten, not remove, clustered dupes - TokuDB"
   )  or diag($test_diff);
}

SKIP: {
   skip "This test requires MyRocks", 1 if ( !$sb->has_engine('source', 'ROCKSDB') ) ;

   $dbh->do('SET binlog_format="ROW"');
   $dbh->do('ALTER TABLE issue_295.t ENGINE=ROCKSDB');

   # MyRocks returns 0 rows istead of 1 in 5.7
   # As a result, wrong size duplicate indexes reported
   # We are not going to fix this, because 5.7 is EOL
   my $transform_len = undef;
   if ( $sandbox_version ge '5.7' && $sandbox_version lt '8.0' ) {
      $transform_len = sub {
         my $txt = slurp_file(shift);
         $txt =~ s/Size Duplicate Indexes   0/Size Duplicate Indexes   8/g;
         print $txt;
      };
   }

   ok(
      no_diff(
         sub { pt_duplicate_key_checker::main(@args, qw(-d issue_295)) },
         "$sample/issue_295-51.txt",
         transform_sample => $transform_int,
         transform_result => $transform_len,
      ),
      "Shorten, not remove, clustered dupes - MyRocks"
   )  or diag($test_diff);

}

# #############################################################################
# Error if InnoDB table has no PK or unique indexes
# https://bugs.launchpad.net/percona-toolkit/+bug/1036804
# #############################################################################
$sb->load_file('source', "t/pt-duplicate-key-checker/samples/idb-no-uniques-bug-894140.sql");

# PTDEBUG was auto-vivifying $clustered_key:
#
#    PTDEBUG && _d('clustered key:', $clustered_key->{name},
#       $clustered_key->{colnames});
#
#    if ( $clustered_key
#         && $args{clustered}
#         && $args{tbl_info}->{engine}
#         && $args{tbl_info}->{engine} =~ m/InnoDB/i )
#    {
#          push @dupes, $self->remove_clustered_duplicates($clustered_key...
#
#    sub remove_clustered_duplicates {
#       my ( $self, $ck, $keys, %args ) = @_;
#       die "I need a ck argument"   unless $ck;
#       die "I need a keys argument" unless $keys;
#       my $ck_cols = $ck->{colnames};
#       my @dupes;
#       KEY:
#       for my $i ( 0 .. @$keys - 1 ) {
#          my $key = $keys->[$i]->{colnames};
#          if ( $key =~ m/$ck_cols$/ ) {

my $output = `PTDEBUG=1 $trunk/bin/pt-duplicate-key-checker F=$cnf -d bug_1036804 2>&1`;

unlike(
   $output,
   qr/Use of uninitialized value/,
   'PTDEBUG doesn\'t auto-vivify cluster key hashref (bug 1036804)'
);

# #############################################################################
# 
# https://bugs.launchpad.net/percona-toolkit/+bug/1201443
# #############################################################################
$sb->load_file('source', "t/pt-duplicate-key-checker/samples/fk_chosen_index_bug_1201443.sql");

$output = `$trunk/bin/pt-duplicate-key-checker F=$cnf -d fk_chosen_index_bug_1201443 2>&1`;

unlike(
   $output,
   qr/Use of uninitialized value/,
   'fk_chosen_index_bug_1201443'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
done_testing;
