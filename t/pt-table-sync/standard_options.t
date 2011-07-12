#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 3;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

my $output;

# Test DSN value inheritance.
$output = `$trunk/bin/pt-table-sync h=127.1 h=127.2,P=12346 --port 12345 --explain-hosts`;
is(
   $output,
"# DSN: P=12345,h=127.1
# DSN: P=12346,h=127.2
",
   'DSNs inherit values from --port, etc. (issue 248)'
);

# #############################################################################
# Test --explain-hosts (issue 293).
# #############################################################################

# This is redundant; it crept in over time and I keep it for history.

$output = `$trunk/bin/pt-table-sync --explain-hosts localhost,D=foo,t=bar t=baz`;
is($output,
<<EOF
# DSN: D=foo,h=localhost,t=bar
# DSN: D=foo,h=localhost,t=baz
EOF
, '--explain-hosts');

# #############################################################################
# Issue 391: Add --pid option to mk-table-sync
# #############################################################################
`touch /tmp/mk-table-sync.pid`;
$output = `$trunk/bin/pt-table-sync h=127.1,P=12346,u=msandbox,p=msandbox --sync-to-master --print --no-check-triggers --pid /tmp/mk-table-sync.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-table-sync.pid already exists},
   'Dies if PID file already exists (issue 391)'
);

`rm -rf /tmp/mk-table-sync.pid`;

# #############################################################################
# Done.
# #############################################################################
exit;
