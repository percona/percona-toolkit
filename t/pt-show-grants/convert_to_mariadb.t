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
require "$trunk/bin/pt-show-grants";

# This exercises pt_show_grants::convert_to_mariadb() directly, so it
# needs no database connection: it's the pure string-rewriting half of
# --convert-to-MariaDB.  The sub returns a LIST of statements (usually
# just one), so every call below is made in list context.

# The exact statement from PT-2547: a MySQL 8.0 ALTER USER with the
# password-management clauses MariaDB doesn't understand.
is_deeply(
   [ pt_show_grants::convert_to_mariadb(
      q{ALTER USER `wp_lefred`@`127.0.0.1` IDENTIFIED WITH 'mysql_native_password' AS '*FBA161068101DB224E8BE9350119DBF34A897DA4' REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK PASSWORD HISTORY DEFAULT PASSWORD REUSE INTERVAL DEFAULT PASSWORD REQUIRE CURRENT DEFAULT}
   ) ],
   [ q{ALTER USER `wp_lefred`@`127.0.0.1` IDENTIFIED VIA mysql_native_password USING '*FBA161068101DB224E8BE9350119DBF34A897DA4' REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK} ],
   'Converts the PT-2547 ALTER USER statement to valid MariaDB syntax',
);

# auth_socket becomes MariaDB's unix_socket, with no USING clause.
is_deeply(
   [ pt_show_grants::convert_to_mariadb(
      q{ALTER USER `root`@`localhost` IDENTIFIED WITH 'auth_socket' REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK}
   ) ],
   [ q{ALTER USER `root`@`localhost` IDENTIFIED VIA unix_socket REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK} ],
   'Converts auth_socket to unix_socket',
);

# PASSWORD REQUIRE CURRENT can appear without a trailing DEFAULT/OPTIONAL.
is_deeply(
   [ pt_show_grants::convert_to_mariadb(
      q{ALTER USER `u`@`%` IDENTIFIED WITH 'mysql_native_password' AS 'hash' PASSWORD REQUIRE CURRENT ACCOUNT LOCK}
   ) ],
   [ q{ALTER USER `u`@`%` IDENTIFIED VIA mysql_native_password USING 'hash' ACCOUNT LOCK} ],
   'Strips a bare PASSWORD REQUIRE CURRENT clause',
);

# A statement with no IDENTIFIED clause, or nothing to convert, passes
# through untouched (aside from stripped MySQL-8-only clauses).
is_deeply(
   [ pt_show_grants::convert_to_mariadb(
      q{CREATE USER IF NOT EXISTS `sally`@`%`}
   ) ],
   [ q{CREATE USER IF NOT EXISTS `sally`@`%`} ],
   'Leaves a statement with no IDENTIFIED clause unchanged',
);

is_deeply(
   [ pt_show_grants::convert_to_mariadb(undef) ],
   [],
   'Handles undef input gracefully',
);

# An unmapped plugin with a plain quoted auth string (e.g.
# sha256_password) still gets its syntax rewritten, and a warning is
# issued -- there's no way to make the password actually work, but the
# statement at least becomes valid SQL.
{
   my $warning;
   local $SIG{__WARN__} = sub { $warning = $_[0]; };
   is_deeply(
      [ pt_show_grants::convert_to_mariadb(
         q{ALTER USER `x`@`%` IDENTIFIED WITH 'sha256_password' AS '$5$somehash'}
      ) ],
      [ q{ALTER USER `x`@`%` IDENTIFIED VIA sha256_password USING '$5$somehash'} ],
      'Rewrites the syntax even for a plugin with no MariaDB equivalent',
   );
   like(
      $warning,
      qr/sha256_password.*no direct MariaDB equivalent/,
      'Warns about the unmapped plugin',
   );
}

# caching_sha2_password has no MariaDB-compatible ALTER USER path (its
# grammar only accepts a quoted string literal for the auth string, and
# this plugin's hash is binary, which is why MySQL prints it as a 0x...
# hex literal in the first place). The IDENTIFIED clause is dropped
# from the ALTER USER entirely -- the tool does not install any plugin
# -- and instead the plugin name and the unhexed hash are written
# straight into mysql.global_priv, followed by a flush so the change
# actually takes effect. Verified against a live MariaDB 11.4 server;
# actually logging in still requires a compatible plugin (e.g.
# MariaDB's own auth_mysql_sha2) to be installed and active on the
# target server -- this tool leaves that to the DBA.
is_deeply(
   [ pt_show_grants::convert_to_mariadb(
      q{ALTER USER `lefred`@`%` IDENTIFIED WITH caching_sha2_password AS 0x2441 REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK},
      'lefred', '%',
   ) ],
   [
      q{ALTER USER `lefred`@`%` REQUIRE NONE PASSWORD EXPIRE DEFAULT ACCOUNT UNLOCK},
      q{UPDATE mysql.global_priv SET Priv = JSON_SET(Priv, '$.plugin', 'caching_sha2_password', '$.authentication_string', UNHEX('2441')) WHERE User = 'lefred' AND Host = '%'},
      q{FLUSH PRIVILEGES},
   ],
   'Converts a caching_sha2_password ALTER USER into the stripped ALTER USER plus a raw global_priv update, with no INSTALL SONAME',
);

# Without a user/host to target, there's nothing safe to UPDATE, so it
# just warns instead of guessing -- but the IDENTIFIED clause is still
# dropped, since it wouldn't work against MariaDB either way.
{
   my $warning;
   local $SIG{__WARN__} = sub { $warning = $_[0]; };
   is_deeply(
      [ pt_show_grants::convert_to_mariadb(
         q{ALTER USER `lefred`@`%` IDENTIFIED WITH caching_sha2_password AS 0x2441}
      ) ],
      [ q{ALTER USER `lefred`@`%`} ],
      'Still drops the IDENTIFIED clause when no user/host is given',
   );
   like(
      $warning,
      qr/caching_sha2_password.*usable hex-encoded auth string/,
      'Warns when it cannot target a global_priv update',
   );
}

done_testing;
