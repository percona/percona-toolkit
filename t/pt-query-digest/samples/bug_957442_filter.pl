use strict;
use warnings FATAL => 'all';
use Data::Dumper;
my $page = 0;
if ( $event->{arg} ) {
   ($page) = $event->{arg} =~ m#/\*page_(\d+)\*/#g;
}
$event->{page} = ($page || 0);
1
