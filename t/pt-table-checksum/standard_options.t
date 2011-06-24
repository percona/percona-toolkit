#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 2;

use MaatkitTest;
require "$trunk/bin/pt-table-checksum";

my $output;

# Test DSN value inheritance
$output = `$trunk/bin/pt-table-checksum h=127.1 h=127.2,P=12346 --port 12345 --explain-hosts`;
like(
   $output,
   qr/^Server 127.1:\s+P=12345,h=127.1\s+Server 127.2:\s+P=12346,h=127.2/,
   'DSNs inherit values from --port, etc. (issue 248)'
);

# #########################################################################
# Issue 391: Add --pid option to all scripts
# #########################################################################
`touch /tmp/mk-script.pid`;
$output = `$trunk/bin/pt-table-checksum h=127.1,P=12345,u=msandbox,p=msandbox -d test -t issue_122,issue_94 --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid already exists},
   'Dies if PID file already exists (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;

# #############################################################################
# Done.
# #############################################################################
exit;
