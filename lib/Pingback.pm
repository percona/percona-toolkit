package Pingback;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

local $EVAL_ERROR;
eval {
   require HTTP::Tiny;
   require Transformers;
};

sub pingback {
   my ($url, $ua) = @_;
   $ua ||= HTTP::Tiny->new( verify_ssl => 1 );

   my $response = $ua->get($url);

   if ( $response->{status} >= 500
         || (exists $response->{reason} && !exists $response->{content}) )
   {
      return;
   }

   my $checks = $response->{content}
              ? eval($response->{content})
              : _default_checks();
   my $e = $EVAL_ERROR;
   $checks ||= _default_checks();
   $checks->{check_code_error} = $e if $EVAL_ERROR;

   my $options = {
      headers  => { 'content-type'   => 'application/json', },
      content  => Transformers::encode_json($checks),
   };

   return $ua->post($url, $options);
}

sub _default_checks {
   return +{
         perl_version      => $],
         DBD_mysql_version => $DBD::mysql::VERSION || 'N/A',
         operating_system  => $^O eq "MSWin32" ? Win32::GetOSName() : $^O,
   };
}

1;
