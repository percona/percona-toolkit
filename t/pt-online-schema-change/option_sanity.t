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

my $output  = "";
my $cmd     = "$trunk/bin/pt-online-schema-change";

$output = `$cmd`;
like(
   $output,
   qr/DSN must be specified/,
   "Must specify a DSN with t part"
);

$output = `$cmd h=127.1,P=12345,t=tbl`;
like(
   $output,
   qr/DSN must specify a database \(D\) and a table \(t\)/,
   "DSN must specify a D part"
);

$output = `$cmd h=127.1,P=12345,u=msandbox,p=msandbox,D=mysql`;
like(
   $output,
   qr/DSN must specify a database \(D\) and a table \(t\)/,
   "DSN must specify t part"
);

$output = `$cmd h=127.1,P=12345,u=msandbox,p=msandbox h=127.1`;
like(
   $output,
   qr/Specify only one DSN/,
   "Only 1 DSN allowed"
);

$output = `$cmd --help`;
like(
   $output,
   qr/--execute\s+FALSE/,
   "--execute FALSE by default"
);

like(
   $output,
   qr/--statistics\s+FALSE/,
   "--statistics is FALSE by default"
);

$output = `$cmd h=127.1,P=12345,u=msandbox,p=msandbox --alter-foreign-keys-method drop_swap --no-drop-new-table`;
like(
   $output,
   qr/--alter-foreign-keys-method=drop_swap does not work with --no-drop-new-table/,
   "Cannot --alter-foreign-keys-method=drop_swap with --no-drop-new-table"
);

$output = `$cmd h=127.1,P=12345,u=msandbox,p=msandbox,D=mysql,t=user --max-load 100 --alter "ENGINE=MyISAM" --dry-run`;
like(
   $output,
   qr/Invalid --max-load/,
   "Validates --max-load"
);

$output = `$cmd h=127.1,P=12345,u=msandbox,p=msandbox,D=mysql,t=user --critical-load 100 --alter "ENGINE=MyISAM" --dry-run`;
like(
   $output,
   qr/Invalid --critical-load/,
   "Validates --critical-load"
);

# #############################################################################
# Done.
# #############################################################################
done_testing;
