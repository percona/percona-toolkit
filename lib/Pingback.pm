package Pingback;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

local $EVAL_ERROR;
eval {
   require HTTPMicro;
   require VersionCheck;
};

sub pingback {
   my ($url, $dbh, $ua) = @_; # pingback($url, $dbh[, $ua])
   $ua ||= HTTP::Micro->new();

   my $response = $ua->request('GET', $url);

   if ( $response->{status} >= 500
         ||  exists $response->{reason}
         || !exists $response->{content} )
   {
      return;
   }

   my $items  = VersionCheck->parse_server_response(response => $response->{content});
   my $checks = VersionCheck->get_versions(items => $items, dbh => $dbh);

   my $options = { content => encode_to_plaintext($checks) };

   return $ua->request('POST', $url, $options);
}

sub encode_to_plaintext {
   my $data = shift;
   return join "\n", map { "$_,$data->{$_}" } keys %$data;
}

1;
