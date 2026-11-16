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

require "$ENV{PERCONA_TOOLKIT_BRANCH}/bin/pt-heartbeat";

{
   package HeartbeatReadOnlyDbh;

   sub new {
      my ( $class, %args ) = @_;
      return bless \%args, $class;
   }

   sub selectrow_array {
      my ( $self, $sql ) = @_;
      die "Unexpected query: $sql\n" unless $sql eq 'SHOW GRANTS';
      die "Cannot read grants\n" if $self->{grant_error};
      return $self->{grants};
   }

   sub selectall_arrayref {
      my ( $self, $sql ) = @_;
      die "Unexpected query: $sql\n" unless $sql =~ /^SHOW GLOBAL VARIABLES/;
      die $self->{error} if $self->{error};
      return [ map { [ $_, $self->{variables}->{$_} ] }
         sort keys %{$self->{variables}} ];
   }
}

my $ordinary = q{GRANT SELECT ON *.* TO 'heartbeat'@'localhost'};
my $super    = q{GRANT SUPER ON *.* TO 'heartbeat'@'localhost'};
my $all      = q{GRANT ALL PRIVILEGES ON *.* TO 'heartbeat'@'localhost'};

for my $case (
   [ 'MariaDB writable',                 'OFF', undef, $ordinary, 0 ],
   [ 'MariaDB read-only',                'ON',  undef, $ordinary, 1 ],
   [ 'MariaDB SUPER bypass',             'ON',  undef, $super,    0 ],
   [ 'MariaDB ALL bypass',               'ON',  undef, $all,      0 ],
   [ 'MySQL writable',                   'OFF', 'OFF', $ordinary, 0 ],
   [ 'MySQL super-read-only with SUPER',  'ON',  'ON',  $super,    1 ],
   [ 'MariaDB NO_LOCK_NO_ADMIN with ALL', 'NO_LOCK_NO_ADMIN', undef, $all, 1 ],
) {
   my ( $name, $read_only, $super_read_only, $grants, $expected ) = @$case;
   subtest $name => sub {
      my %variables = ( read_only => $read_only );
      $variables{super_read_only} = $super_read_only
         if defined $super_read_only;
      my $dbh = HeartbeatReadOnlyDbh->new(
         variables => \%variables, grants => $grants);
      my $actual = eval { pt_heartbeat::server_is_readonly($dbh) };
      is($EVAL_ERROR, '', 'Read-only check succeeds');
      is($actual ? 1 : 0, $expected, 'Honors the server read-only state');
   };
}

my $dbh = HeartbeatReadOnlyDbh->new(
   variables => { read_only => 'ON' }, grant_error => 1);
ok(eval { pt_heartbeat::server_is_readonly($dbh) },
   'Failure to inspect grants does not bypass read-only protection');

$dbh = HeartbeatReadOnlyDbh->new(
   variables => {}, error => "Connection lost\n");
eval { pt_heartbeat::server_is_readonly($dbh) };
like($EVAL_ERROR, qr/Connection lost/, 'Variable query errors propagate');

$dbh = HeartbeatReadOnlyDbh->new(variables => {});
eval { pt_heartbeat::server_is_readonly($dbh) };
like($EVAL_ERROR, qr/Cannot determine.*read_only/,
   'Missing read_only is not treated as a writable server');

done_testing;
