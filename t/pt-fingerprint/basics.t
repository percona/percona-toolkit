#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 7;

use PerconaTest;
require "$trunk/bin/pt-fingerprint";

my @args   = qw();
my $output;
my $sample = "$trunk/t/pt-fingerprint/samples";
my $pqd    = "$trunk/bin/pt-query-digest";

$output = `$trunk/bin/pt-fingerprint --help`;
like(
   $output,
   qr/--help/,
   "It runs"
);


sub test_query_file {
   my ($file) = @_;
   if ( ! -f "$sample/$file.fingerprint" ) {
      `$pqd --fingerprint $sample/$file | awk '/Fingerprint/ { getline; print; exit; }' | sed -e 's/^#[ ]*//' > $sample/$file.fingerprint`;
      diag("Created $sample/$file.fingerprint");
   }
   chomp(my $expect = `cat $sample/$file.fingerprint`);
   my $got = output(
      sub { pt_fingerprint::main("$sample/$file") }
   );
   chomp($got);
   is(
      $got,
      $expect,
      "$file fingerprint"
   );
};

opendir my $dir, $sample or die "Cannot open $sample: $OS_ERROR\n";
while (defined(my $file = readdir($dir))) {
   next unless $file =~ m/^query\d+$/;
   test_query_file($file);
}
closedir $dir;


sub test_query {
   my (%args) = @_;
   my $query  = $args{query};
   my $expect = $args{expect};
   my @ops    = $args{ops} ? @{$args{ops}} : ();

   $output = output(
      sub { pt_fingerprint::main('--query', $query, @ops) }
   );
   chomp($output);
   is(
      $output,
      $expect,
      $args{name} ? $args{name} : "Fingerprint " . substr($query, 0, 70)
   );
}

test_query(
   query  => 'select * from tbl where id=1',
   expect => 'select * from tbl where id=?',
);

test_query(
   name   => "Fingerprint MD5_word",
   query  => "SELECT c FROM db.fbc5e685a5d3d45aa1d0347fdb7c4d35_temp where id=1",
   expect => "select c from db.?_temp where id=?",
   ops    => [qw(--match-md5-checksums)],
);

test_query(
   name   => "Fingerprint word_MD5",
   query  => "SELECT c FROM db.temp_fbc5e685a5d3d45aa1d0347fdb7c4d35 where id=1",
   expect => "select c from db.temp_? where id=?",
   ops    => [qw(--match-md5-checksums)],
);

test_query(
   name   => "Fingerprint word<number>",
   query  => "SELECT c FROM db.catch22 WHERE id is null",
   expect => "select c from db.catch22 where id is ?",
   ops    => [qw(--match-embedded-numbers)],
);
# #############################################################################
# Done.
# #############################################################################
exit;
