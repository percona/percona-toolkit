# This package is a copy without comments from the original.  
# The original with comments and its test file can be found at: 
# https://metacpan.org/pod/HTTP::Tiny
package HTTP::Tiny;
use strict;
use warnings;
# ABSTRACT: A small, simple, correct HTTP/1.1 client

our $VERSION = '0.077';

sub _croak { require Carp; Carp::croak(@_) }

my @attributes;
BEGIN {
    @attributes = qw(
        cookie_jar default_headers http_proxy https_proxy keep_alive
        local_address max_redirect max_size proxy no_proxy
        SSL_options verify_SSL
    );
    my %persist_ok = map {; $_ => 1 } qw(
        cookie_jar default_headers max_redirect max_size
    );
    no strict 'refs';
    no warnings 'uninitialized';
    for my $accessor ( @attributes ) {
        *{$accessor} = sub {
            @_ > 1
                ? do {
                    delete $_[0]->{handle} if !$persist_ok{$accessor} && $_[1] ne $_[0]->{$accessor};
                    $_[0]->{$accessor} = $_[1]
                }
                : $_[0]->{$accessor};
        };
    }
}

sub agent {
    my($self, $agent) = @_;
    if( @_ > 1 ){
        $self->{agent} =
            (defined $agent && $agent =~ / $/) ? $agent . $self->_agent : $agent;
    }
    return $self->{agent};
}

sub timeout {
    my ($self, $timeout) = @_;
    if ( @_ > 1 ) {
        $self->{timeout} = $timeout;
        if ($self->{handle}) {
            $self->{handle}->timeout($timeout);
        }
    }
    return $self->{timeout};
}

sub new {
    my($class, %args) = @_;

    my $self = {
        max_redirect => 5,
        timeout      => defined $args{timeout} ? $args{timeout} : 60,
        keep_alive   => 1,
        verify_SSL   => $args{verify_SSL} || $args{verify_ssl} || 0, # no verification by default
        no_proxy     => $ENV{no_proxy},
    };

    bless $self, $class;

    $class->_validate_cookie_jar( $args{cookie_jar} ) if $args{cookie_jar};

    for my $key ( @attributes ) {
        $self->{$key} = $args{$key} if exists $args{$key}
    }

    $self->agent( exists $args{agent} ? $args{agent} : $class->_agent );

    $self->_set_proxies;

    return $self;
}

sub _set_proxies {
    my ($self) = @_;

    # get proxies from %ENV only if not provided; explicit undef will disable
    # getting proxies from the environment

    # generic proxy
    if (! exists $self->{proxy} ) {
        $self->{proxy} = $ENV{all_proxy} || $ENV{ALL_PROXY};
    }

    if ( defined $self->{proxy} ) {
        $self->_split_proxy( 'generic proxy' => $self->{proxy} ); # validate
    }
    else {
        delete $self->{proxy};
    }

    # http proxy
    if (! exists $self->{http_proxy} ) {
        # under CGI, bypass HTTP_PROXY as request sets it from Proxy header
        local $ENV{HTTP_PROXY} if $ENV{REQUEST_METHOD};
        $self->{http_proxy} = $ENV{http_proxy} || $ENV{HTTP_PROXY} || $self->{proxy};
    }

    if ( defined $self->{http_proxy} ) {
        $self->_split_proxy( http_proxy => $self->{http_proxy} ); # validate
        $self->{_has_proxy}{http} = 1;
    }
    else {
        delete $self->{http_proxy};
    }

    # https proxy
    if (! exists $self->{https_proxy} ) {
        $self->{https_proxy} = $ENV{https_proxy} || $ENV{HTTPS_PROXY} || $self->{proxy};
    }

    if ( $self->{https_proxy} ) {
        $self->_split_proxy( https_proxy => $self->{https_proxy} ); # validate
        $self->{_has_proxy}{https} = 1;
    }
    else {
        delete $self->{https_proxy};
    }

    # Split no_proxy to array reference if not provided as such
    unless ( ref $self->{no_proxy} eq 'ARRAY' ) {
        $self->{no_proxy} =
            (defined $self->{no_proxy}) ? [ split /\s*,\s*/, $self->{no_proxy} ] : [];
    }

    return;
}

for my $sub_name ( qw/get head put post delete/ ) {
    my $req_method = uc $sub_name;
    no strict 'refs';
    eval <<"HERE"; ## no critic
    sub $sub_name {
        my (\$self, \$url, \$args) = \@_;
        \@_ == 2 || (\@_ == 3 && ref \$args eq 'HASH')
        or _croak(q/Usage: \$http->$sub_name(URL, [HASHREF])/ . "\n");
        return \$self->request('$req_method', \$url, \$args || {});
    }
HERE
}

sub post_form {
    my ($self, $url, $data, $args) = @_;
    (@_ == 3 || @_ == 4 && ref $args eq 'HASH')
        or _croak(q/Usage: $http->post_form(URL, DATAREF, [HASHREF])/ . "\n");

    my $headers = {};
    while ( my ($key, $value) = each %{$args->{headers} || {}} ) {
        $headers->{lc $key} = $value;
    }
    delete $args->{headers};

    return $self->request('POST', $url, {
            %$args,
            content => $self->www_form_urlencode($data),
            headers => {
                %$headers,
                'content-type' => 'application/x-www-form-urlencoded'
            },
        }
    );
}

sub mirror {
    my ($self, $url, $file, $args) = @_;
    @_ == 3 || (@_ == 4 && ref $args eq 'HASH')
      or _croak(q/Usage: $http->mirror(URL, FILE, [HASHREF])/ . "\n");

    if ( exists $args->{headers} ) {
        my $headers = {};
        while ( my ($key, $value) = each %{$args->{headers} || {}} ) {
            $headers->{lc $key} = $value;
        }
        $args->{headers} = $headers;
    }

    if ( -e $file and my $mtime = (stat($file))[9] ) {
        $args->{headers}{'if-modified-since'} ||= $self->_http_date($mtime);
    }
    my $tempfile = $file . int(rand(2**31));

    require Fcntl;
    sysopen my $fh, $tempfile, Fcntl::O_CREAT()|Fcntl::O_EXCL()|Fcntl::O_WRONLY()
       or _croak(qq/Error: Could not create temporary file $tempfile for downloading: $!\n/);
    binmode $fh;
    $args->{data_callback} = sub { print {$fh} $_[0] };
    my $response = $self->request('GET', $url, $args);
    close $fh
        or _croak(qq/Error: Caught error closing temporary file $tempfile: $!\n/);

    if ( $response->{success} ) {
        rename $tempfile, $file
            or _croak(qq/Error replacing $file with $tempfile: $!\n/);
        my $lm = $response->{headers}{'last-modified'};
        if ( $lm and my $mtime = $self->_parse_http_date($lm) ) {
            utime $mtime, $mtime, $file;
        }
    }
    $response->{success} ||= $response->{status} eq '304';
    unlink $tempfile;
    return $response;
}

my %idempotent = map { $_ => 1 } qw/GET HEAD PUT DELETE OPTIONS TRACE/;

sub request {
    my ($self, $method, $url, $args) = @_;
    @_ == 3 || (@_ == 4 && ref $args eq 'HASH')
      or _croak(q/Usage: $http->request(METHOD, URL, [HASHREF])/ . "\n");
    $args ||= {}; # we keep some state in this during _request

    # RFC 2616 Section 8.1.4 mandates a single retry on broken socket
    my $response;
    for ( 0 .. 1 ) {
        $response = eval { $self->_request($method, $url, $args) };
        last unless $@ && $idempotent{$method}
            && $@ =~ m{^(?:Socket closed|Unexpected end)};
    }

    if (my $e = $@) {
        # maybe we got a response hash thrown from somewhere deep
        if ( ref $e eq 'HASH' && exists $e->{status} ) {
            $e->{redirects} = delete $args->{_redirects} if @{ $args->{_redirects} || []};
            return $e;
        }

        # otherwise, stringify it
        $e = "$e";
        $response = {
            url     => $url,
            success => q{},
            status  => 599,
            reason  => 'Internal Exception',
            content => $e,
            headers => {
                'content-type'   => 'text/plain',
                'content-length' => length $e,
            },
            ( @{$args->{_redirects} || []} ? (redirects => delete $args->{_redirects}) : () ),
        };
    }
    return $response;
}

sub www_form_urlencode {
    my ($self, $data) = @_;
    (@_ == 2 && ref $data)
        or _croak(q/Usage: $http->www_form_urlencode(DATAREF)/ . "\n");
    (ref $data eq 'HASH' || ref $data eq 'ARRAY')
        or _croak("form data must be a hash or array reference\n");

    my @params = ref $data eq 'HASH' ? %$data : @$data;
    @params % 2 == 0
        or _croak("form data reference must have an even number of terms\n");

    my @terms;
    while( @params ) {
        my ($key, $value) = splice(@params, 0, 2);
        if ( ref $value eq 'ARRAY' ) {
            unshift @params, map { $key => $_ } @$value;
        }
        else {
            push @terms, join("=", map { $self->_uri_escape($_) } $key, $value);
        }
    }

    return join("&", (ref $data eq 'ARRAY') ? (@terms) : (sort @terms) );
}

sub can_ssl {
    my ($self) = @_;

    my($ok, $reason) = (1, '');

    # Need IO::Socket::SSL 1.42 for SSL_create_ctx_callback
    local @INC = @INC;
    pop @INC if $INC[-1] eq '.';
    unless (eval {require IO::Socket::SSL; IO::Socket::SSL->VERSION(1.42)}) {
        $ok = 0;
        $reason .= qq/IO::Socket::SSL 1.42 must be installed for https support\n/;
    }

    # Need Net::SSLeay 1.49 for MODE_AUTO_RETRY
    unless (eval {require Net::SSLeay; Net::SSLeay->VERSION(1.49)}) {
        $ok = 0;
        $reason .= qq/Net::SSLeay 1.49 must be installed for https support\n/;
    }

    # If an object, check that SSL config lets us get a CA if necessary
    if ( ref($self) && ( $self->{verify_SSL} || $self->{SSL_options}{SSL_verify_mode} ) ) {
        my $handle = HTTP::Tiny::Handle->new(
            SSL_options => $self->{SSL_options},
            verify_SSL  => $self->{verify_SSL},
        );
        unless ( eval { $handle->_find_CA_file; 1 } ) {
            $ok = 0;
            $reason .= "$@";
        }
    }

    wantarray ? ($ok, $reason) : $ok;
}

sub connected {
    my ($self) = @_;

    # If a socket exists...
    if ($self->{handle} && $self->{handle}{fh}) {
        my $socket = $self->{handle}{fh};

        # ...and is connected, return the peer host and port.
        if ($socket->connected) {
            return wantarray
                ? ($socket->peerhost, $socket->peerport)
                : join(':', $socket->peerhost, $socket->peerport);
        }
    }
    return;
}

#--------------------------------------------------------------------------#
# private methods
#--------------------------------------------------------------------------#

my %DefaultPort = (
    http => 80,
    https => 443,
);

sub _agent {
    my $class = ref($_[0]) || $_[0];
    (my $default_agent = $class) =~ s{::}{-}g;
    return $default_agent . "/" . $class->VERSION;
}

sub _request {
    my ($self, $method, $url, $args) = @_;

    my ($scheme, $host, $port, $path_query, $auth) = $self->_split_url($url);

    my $request = {
        method    => $method,
        scheme    => $scheme,
        host      => $host,
        port      => $port,
        host_port => ($port == $DefaultPort{$scheme} ? $host : "$host:$port"),
        uri       => $path_query,
        headers   => {},
    };

    my $peer = $args->{peer} || $host;

    # Allow 'peer' to be a coderef.
    if ('CODE' eq ref $peer) {
        $peer = $peer->($host);
    }

    # We remove the cached handle so it is not reused in the case of redirect.
    # If all is well, it will be recached at the end of _request.  We only
    # reuse for the same scheme, host and port
    my $handle = delete $self->{handle};
    if ( $handle ) {
        unless ( $handle->can_reuse( $scheme, $host, $port, $peer ) ) {
            $handle->close;
            undef $handle;
        }
    }
    $handle ||= $self->_open_handle( $request, $scheme, $host, $port, $peer );

    $self->_prepare_headers_and_cb($request, $args, $url, $auth);
    $handle->write_request($request);

    my $response;
    do { $response = $handle->read_response_header }
        until (substr($response->{status},0,1) ne '1');

    $self->_update_cookie_jar( $url, $response ) if $self->{cookie_jar};
    my @redir_args = $self->_maybe_redirect($request, $response, $args);

    my $known_message_length;
    if ($method eq 'HEAD' || $response->{status} =~ /^[23]04/) {
        # response has no message body
        $known_message_length = 1;
    }
    else {
        # Ignore any data callbacks during redirection.
        my $cb_args = @redir_args ? +{} : $args;
        my $data_cb = $self->_prepare_data_cb($response, $cb_args);
        $known_message_length = $handle->read_body($data_cb, $response);
    }

    if ( $self->{keep_alive}
        && $known_message_length
        && $response->{protocol} eq 'HTTP/1.1'
        && ($response->{headers}{connection} || '') ne 'close'
    ) {
        $self->{handle} = $handle;
    }
    else {
        $handle->close;
    }

    $response->{success} = substr( $response->{status}, 0, 1 ) eq '2';
    $response->{url} = $url;

    # Push the current response onto the stack of redirects if redirecting.
    if (@redir_args) {
        push @{$args->{_redirects}}, $response;
        return $self->_request(@redir_args, $args);
    }

    # Copy the stack of redirects into the response before returning.
    $response->{redirects} = delete $args->{_redirects}
      if @{$args->{_redirects}};
    return $response;
}

sub _open_handle {
    my ($self, $request, $scheme, $host, $port, $peer) = @_;

    my $handle  = HTTP::Tiny::Handle->new(
        timeout         => $self->{timeout},
        SSL_options     => $self->{SSL_options},
        verify_SSL      => $self->{verify_SSL},
        local_address   => $self->{local_address},
        keep_alive      => $self->{keep_alive}
    );

    if ($self->{_has_proxy}{$scheme} && ! grep { $host =~ /\Q$_\E$/ } @{$self->{no_proxy}}) {
        return $self->_proxy_connect( $request, $handle );
    }
    else {
        return $handle->connect($scheme, $host, $port, $peer);
    }
}

sub _proxy_connect {
    my ($self, $request, $handle) = @_;

    my @proxy_vars;
    if ( $request->{scheme} eq 'https' ) {
        _croak(qq{No https_proxy defined}) unless $self->{https_proxy};
        @proxy_vars = $self->_split_proxy( https_proxy => $self->{https_proxy} );
        if ( $proxy_vars[0] eq 'https' ) {
            _croak(qq{Can't proxy https over https: $request->{uri} via $self->{https_proxy}});
        }
    }
    else {
        _croak(qq{No http_proxy defined}) unless $self->{http_proxy};
        @proxy_vars = $self->_split_proxy( http_proxy => $self->{http_proxy} );
    }

    my ($p_scheme, $p_host, $p_port, $p_auth) = @proxy_vars;

    if ( length $p_auth && ! defined $request->{headers}{'proxy-authorization'} ) {
        $self->_add_basic_auth_header( $request, 'proxy-authorization' => $p_auth );
    }

    $handle->connect($p_scheme, $p_host, $p_port, $p_host);

    if ($request->{scheme} eq 'https') {
        $self->_create_proxy_tunnel( $request, $handle );
    }
    else {
        # non-tunneled proxy requires absolute URI
        $request->{uri} = "$request->{scheme}://$request->{host_port}$request->{uri}";
    }

    return $handle;
}

sub _split_proxy {
    my ($self, $type, $proxy) = @_;

    my ($scheme, $host, $port, $path_query, $auth) = eval { $self->_split_url($proxy) };

    unless(
        defined($scheme) && length($scheme) && length($host) && length($port)
        && $path_query eq '/'
    ) {
        _croak(qq{$type URL must be in format http[s]://[auth@]<host>:<port>/\n});
    }

    return ($scheme, $host, $port, $auth);
}

sub _create_proxy_tunnel {
    my ($self, $request, $handle) = @_;

    $handle->_assert_ssl;

    my $agent = exists($request->{headers}{'user-agent'})
        ? $request->{headers}{'user-agent'} : $self->{agent};

    my $connect_request = {
        method    => 'CONNECT',
        uri       => "$request->{host}:$request->{port}",
        headers   => {
            host => "$request->{host}:$request->{port}",
            'user-agent' => $agent,
        }
    };

    if ( $request->{headers}{'proxy-authorization'} ) {
        $connect_request->{headers}{'proxy-authorization'} =
            delete $request->{headers}{'proxy-authorization'};
    }

    $handle->write_request($connect_request);
    my $response;
    do { $response = $handle->read_response_header }
        until (substr($response->{status},0,1) ne '1');

    # if CONNECT failed, throw the response so it will be
    # returned from the original request() method;
    unless (substr($response->{status},0,1) eq '2') {
        die $response;
    }

    # tunnel established, so start SSL handshake
    $handle->start_ssl( $request->{host} );

    return;
}

sub _prepare_headers_and_cb {
    my ($self, $request, $args, $url, $auth) = @_;

    for ($self->{default_headers}, $args->{headers}) {
        next unless defined;
        while (my ($k, $v) = each %$_) {
            $request->{headers}{lc $k} = $v;
            $request->{header_case}{lc $k} = $k;
        }
    }

    if (exists $request->{headers}{'host'}) {
        die(qq/The 'Host' header must not be provided as header option\n/);
    }

    $request->{headers}{'host'}         = $request->{host_port};
    $request->{headers}{'user-agent'} ||= $self->{agent};
    $request->{headers}{'connection'}   = "close"
        unless $self->{keep_alive};

    if ( defined $args->{content} ) {
        if (ref $args->{content} eq 'CODE') {
            $request->{headers}{'content-type'} ||= "application/octet-stream";
            $request->{headers}{'transfer-encoding'} = 'chunked'
              unless $request->{headers}{'content-length'}
                  || $request->{headers}{'transfer-encoding'};
            $request->{cb} = $args->{content};
        }
        elsif ( length $args->{content} ) {
            my $content = $args->{content};
            if ( $] ge '5.008' ) {
                utf8::downgrade($content, 1)
                    or die(qq/Wide character in request message body\n/);
            }
            $request->{headers}{'content-type'} ||= "application/octet-stream";
            $request->{headers}{'content-length'} = length $content
              unless $request->{headers}{'content-length'}
                  || $request->{headers}{'transfer-encoding'};
            $request->{cb} = sub { substr $content, 0, length $content, '' };
        }
        $request->{trailer_cb} = $args->{trailer_callback}
            if ref $args->{trailer_callback} eq 'CODE';
    }

    ### If we have a cookie jar, then maybe add relevant cookies
    if ( $self->{cookie_jar} ) {
        my $cookies = $self->cookie_jar->cookie_header( $url );
        $request->{headers}{cookie} = $cookies if length $cookies;
    }

    # if we have Basic auth parameters, add them
    if ( length $auth && ! defined $request->{headers}{authorization} ) {
        $self->_add_basic_auth_header( $request, 'authorization' => $auth );
    }

    return;
}

sub _add_basic_auth_header {
    my ($self, $request, $header, $auth) = @_;
    require MIME::Base64;
    $request->{headers}{$header} =
        "Basic " . MIME::Base64::encode_base64($auth, "");
    return;
}

sub _prepare_data_cb {
    my ($self, $response, $args) = @_;
    my $data_cb = $args->{data_callback};
    $response->{content} = '';

    if (!$data_cb || $response->{status} !~ /^2/) {
        if (defined $self->{max_size}) {
            $data_cb = sub {
                $_[1]->{content} .= $_[0];
                die(qq/Size of response body exceeds the maximum allowed of $self->{max_size}\n/)
                  if length $_[1]->{content} > $self->{max_size};
            };
        }
        else {
            $data_cb = sub { $_[1]->{content} .= $_[0] };
        }
    }
    return $data_cb;
}

sub _update_cookie_jar {
    my ($self, $url, $response) = @_;

    my $cookies = $response->{headers}->{'set-cookie'};
    return unless defined $cookies;

    my @cookies = ref $cookies ? @$cookies : $cookies;

    $self->cookie_jar->add( $url, $_ ) for @cookies;

    return;
}

sub _validate_cookie_jar {
    my ($class, $jar) = @_;

    # duck typing
    for my $method ( qw/add cookie_header/ ) {
        _croak(qq/Cookie jar must provide the '$method' method\n/)
            unless ref($jar) && ref($jar)->can($method);
    }

    return;
}

sub _maybe_redirect {
    my ($self, $request, $response, $args) = @_;
    my $headers = $response->{headers};
    my ($status, $method) = ($response->{status}, $request->{method});
    $args->{_redirects} ||= [];

    if (($status eq '303' or ($status =~ /^30[1278]/ && $method =~ /^GET|HEAD$/))
        and $headers->{location}
        and @{$args->{_redirects}} < $self->{max_redirect}
    ) {
        my $location = ($headers->{location} =~ /^\//)
            ? "$request->{scheme}://$request->{host_port}$headers->{location}"
            : $headers->{location} ;
        return (($status eq '303' ? 'GET' : $method), $location);
    }
    return;
}

sub _split_url {
    my $url = pop;

    # URI regex adapted from the URI module
    my ($scheme, $host, $path_query) = $url =~ m<\A([^:/?#]+)://([^/?#]*)([^#]*)>
      or die(qq/Cannot parse URL: '$url'\n/);

    $scheme     = lc $scheme;
    $path_query = "/$path_query" unless $path_query =~ m<\A/>;

    my $auth = '';
    if ( (my $i = index $host, '@') != -1 ) {
        # user:pass@host
        $auth = substr $host, 0, $i, ''; # take up to the @ for auth
        substr $host, 0, 1, '';          # knock the @ off the host

        # userinfo might be percent escaped, so recover real auth info
        $auth =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    }
    my $port = $host =~ s/:(\d*)\z// && length $1 ? $1
             : $scheme eq 'http'                  ? 80
             : $scheme eq 'https'                 ? 443
             : undef;

    return ($scheme, (length $host ? lc $host : "localhost") , $port, $path_query, $auth);
}

# Date conversions adapted from HTTP::Date
my $DoW = "Sun|Mon|Tue|Wed|Thu|Fri|Sat";
my $MoY = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec";
sub _http_date {
    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($_[1]);
    return sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT",
        substr($DoW,$wday*4,3),
        $mday, substr($MoY,$mon*4,3), $year+1900,
        $hour, $min, $sec
    );
}

sub _parse_http_date {
    my ($self, $str) = @_;
    require Time::Local;
    my @tl_parts;
    if ($str =~ /^[SMTWF][a-z]+, +(\d{1,2}) ($MoY) +(\d\d\d\d) +(\d\d):(\d\d):(\d\d) +GMT$/) {
        @tl_parts = ($6, $5, $4, $1, (index($MoY,$2)/4), $3);
    }
    elsif ($str =~ /^[SMTWF][a-z]+, +(\d\d)-($MoY)-(\d{2,4}) +(\d\d):(\d\d):(\d\d) +GMT$/ ) {
        @tl_parts = ($6, $5, $4, $1, (index($MoY,$2)/4), $3);
    }
    elsif ($str =~ /^[SMTWF][a-z]+ +($MoY) +(\d{1,2}) +(\d\d):(\d\d):(\d\d) +(?:[^0-9]+ +)?(\d\d\d\d)$/ ) {
        @tl_parts = ($5, $4, $3, $2, (index($MoY,$1)/4), $6);
    }
    return eval {
        my $t = @tl_parts ? Time::Local::timegm(@tl_parts) : -1;
        $t < 0 ? undef : $t;
    };
}

# URI escaping adapted from URI::Escape
# c.f. http://www.w3.org/TR/html4/interact/forms.html#h-17.13.4.1
# perl 5.6 ready UTF-8 encoding adapted from JSON::PP
my %escapes = map { chr($_) => sprintf("%%%02X", $_) } 0..255;
$escapes{' '}="+";
my $unsafe_char = qr/[^A-Za-z0-9\-\._~]/;

sub _uri_escape {
    my ($self, $str) = @_;
    if ( $] ge '5.008' ) {
        utf8::encode($str);
    }
    else {
        $str = pack("U*", unpack("C*", $str)) # UTF-8 encode a byte string
            if ( length $str == do { use bytes; length $str } );
        $str = pack("C*", unpack("C*", $str)); # clear UTF-8 flag
    }
    $str =~ s/($unsafe_char)/$escapes{$1}/g;
    return $str;
}

package
    HTTP::Tiny::Handle; # hide from PAUSE/indexers
use strict;
use warnings;

use Errno      qw[EINTR EPIPE];
use IO::Socket qw[SOCK_STREAM];
use Socket     qw[SOL_SOCKET SO_KEEPALIVE];

# PERL_HTTP_TINY_IPV4_ONLY is a private environment variable to force old
# behavior if someone is unable to boostrap CPAN from a new perl install; it is
# not intended for general, per-client use and may be removed in the future
my $SOCKET_CLASS =
    $ENV{PERL_HTTP_TINY_IPV4_ONLY} ? 'IO::Socket::INET' :
    eval { require IO::Socket::IP; IO::Socket::IP->VERSION(0.25) } ? 'IO::Socket::IP' :
    'IO::Socket::INET';

sub BUFSIZE () { 32768 } ## no critic

my $Printable = sub {
    local $_ = shift;
    s/\r/\\r/g;
    s/\n/\\n/g;
    s/\t/\\t/g;
    s/([^\x20-\x7E])/sprintf('\\x%.2X', ord($1))/ge;
    $_;
};

my $Token = qr/[\x21\x23-\x27\x2A\x2B\x2D\x2E\x30-\x39\x41-\x5A\x5E-\x7A\x7C\x7E]/;
my $Field_Content = qr/[[:print:]]+ (?: [\x20\x09]+ [[:print:]]+ )*/x;

sub new {
    my ($class, %args) = @_;
    return bless {
        rbuf             => '',
        timeout          => 60,
        max_line_size    => 16384,
        max_header_lines => 64,
        verify_SSL       => 0,
        SSL_options      => {},
        %args
    }, $class;
}

sub timeout {
    my ($self, $timeout) = @_;
    if ( @_ > 1 ) {
        $self->{timeout} = $timeout;
        if ( $self->{fh} && $self->{fh}->can('timeout') ) {
            $self->{fh}->timeout($timeout);
        }
    }
    return $self->{timeout};
}

sub connect {
    @_ == 5 || die(q/Usage: $handle->connect(scheme, host, port, peer)/ . "\n");
    my ($self, $scheme, $host, $port, $peer) = @_;

    if ( $scheme eq 'https' ) {
        $self->_assert_ssl;
    }
    elsif ( $scheme ne 'http' ) {
      die(qq/Unsupported URL scheme '$scheme'\n/);
    }
    $self->{fh} = $SOCKET_CLASS->new(
        PeerHost  => $peer,
        PeerPort  => $port,
        $self->{local_address} ?
            ( LocalAddr => $self->{local_address} ) : (),
        Proto     => 'tcp',
        Type      => SOCK_STREAM,
        Timeout   => $self->{timeout},
    ) or die(qq/Could not connect to '$host:$port': $@\n/);

    binmode($self->{fh})
      or die(qq/Could not binmode() socket: '$!'\n/);

    if ( $self->{keep_alive} ) {
        unless ( defined( $self->{fh}->setsockopt( SOL_SOCKET, SO_KEEPALIVE, 1 ) ) ) {
            CORE::close($self->{fh});
            die(qq/Could not set SO_KEEPALIVE on socket: '$!'\n/);
        }
    }

    $self->start_ssl($host) if $scheme eq 'https';

    $self->{scheme} = $scheme;
    $self->{host} = $host;
    $self->{peer} = $peer;
    $self->{port} = $port;
    $self->{pid} = $$;
    $self->{tid} = _get_tid();

    return $self;
}

sub start_ssl {
    my ($self, $host) = @_;

    # As this might be used via CONNECT after an SSL session
    # to a proxy, we shut down any existing SSL before attempting
    # the handshake
    if ( ref($self->{fh}) eq 'IO::Socket::SSL' ) {
        unless ( $self->{fh}->stop_SSL ) {
            my $ssl_err = IO::Socket::SSL->errstr;
            die(qq/Error halting prior SSL connection: $ssl_err/);
        }
    }

    my $ssl_args = $self->_ssl_args($host);
    IO::Socket::SSL->start_SSL(
        $self->{fh},
        %$ssl_args,
        SSL_create_ctx_callback => sub {
            my $ctx = shift;
            Net::SSLeay::CTX_set_mode($ctx, Net::SSLeay::MODE_AUTO_RETRY());
        },
    );

    unless ( ref($self->{fh}) eq 'IO::Socket::SSL' ) {
        my $ssl_err = IO::Socket::SSL->errstr;
        die(qq/SSL connection failed for $host: $ssl_err\n/);
    }
}

sub close {
    @_ == 1 || die(q/Usage: $handle->close()/ . "\n");
    my ($self) = @_;
    CORE::close($self->{fh})
      or die(qq/Could not close socket: '$!'\n/);
}

sub write {
    @_ == 2 || die(q/Usage: $handle->write(buf)/ . "\n");
    my ($self, $buf) = @_;

    if ( $] ge '5.008' ) {
        utf8::downgrade($buf, 1)
            or die(qq/Wide character in write()\n/);
    }

    my $len = length $buf;
    my $off = 0;

    local $SIG{PIPE} = 'IGNORE';

    while () {
        $self->can_write
          or die(qq/Timed out while waiting for socket to become ready for writing\n/);
        my $r = syswrite($self->{fh}, $buf, $len, $off);
        if (defined $r) {
            $len -= $r;
            $off += $r;
            last unless $len > 0;
        }
        elsif ($! == EPIPE) {
            die(qq/Socket closed by remote server: $!\n/);
        }
        elsif ($! != EINTR) {
            if ($self->{fh}->can('errstr')){
                my $err = $self->{fh}->errstr();
                die (qq/Could not write to SSL socket: '$err'\n /);
            }
            else {
                die(qq/Could not write to socket: '$!'\n/);
            }

        }
    }
    return $off;
}

sub read {
    @_ == 2 || @_ == 3 || die(q/Usage: $handle->read(len [, allow_partial])/ . "\n");
    my ($self, $len, $allow_partial) = @_;

    my $buf  = '';
    my $got = length $self->{rbuf};

    if ($got) {
        my $take = ($got < $len) ? $got : $len;
        $buf  = substr($self->{rbuf}, 0, $take, '');
        $len -= $take;
    }

    while ($len > 0) {
        $self->can_read
          or die(q/Timed out while waiting for socket to become ready for reading/ . "\n");
        my $r = sysread($self->{fh}, $buf, $len, length $buf);
        if (defined $r) {
            last unless $r;
            $len -= $r;
        }
        elsif ($! != EINTR) {
            if ($self->{fh}->can('errstr')){
                my $err = $self->{fh}->errstr();
                die (qq/Could not read from SSL socket: '$err'\n /);
            }
            else {
                die(qq/Could not read from socket: '$!'\n/);
            }
        }
    }
    if ($len && !$allow_partial) {
        die(qq/Unexpected end of stream\n/);
    }
    return $buf;
}

sub readline {
    @_ == 1 || die(q/Usage: $handle->readline()/ . "\n");
    my ($self) = @_;

    while () {
        if ($self->{rbuf} =~ s/\A ([^\x0D\x0A]* \x0D?\x0A)//x) {
            return $1;
        }
        if (length $self->{rbuf} >= $self->{max_line_size}) {
            die(qq/Line size exceeds the maximum allowed size of $self->{max_line_size}\n/);
        }
        $self->can_read
          or die(qq/Timed out while waiting for socket to become ready for reading\n/);
        my $r = sysread($self->{fh}, $self->{rbuf}, BUFSIZE, length $self->{rbuf});
        if (defined $r) {
            last unless $r;
        }
        elsif ($! != EINTR) {
            if ($self->{fh}->can('errstr')){
                my $err = $self->{fh}->errstr();
                die (qq/Could not read from SSL socket: '$err'\n /);
            }
            else {
                die(qq/Could not read from socket: '$!'\n/);
            }
        }
    }
    die(qq/Unexpected end of stream while looking for line\n/);
}

sub read_header_lines {
    @_ == 1 || @_ == 2 || die(q/Usage: $handle->read_header_lines([headers])/ . "\n");
    my ($self, $headers) = @_;
    $headers ||= {};
    my $lines   = 0;
    my $val;

    while () {
         my $line = $self->readline;

         if (++$lines >= $self->{max_header_lines}) {
             die(qq/Header lines exceeds maximum number allowed of $self->{max_header_lines}\n/);
         }
         elsif ($line =~ /\A ([^\x00-\x1F\x7F:]+) : [\x09\x20]* ([^\x0D\x0A]*)/x) {
             my ($field_name) = lc $1;
             if (exists $headers->{$field_name}) {
                 for ($headers->{$field_name}) {
                     $_ = [$_] unless ref $_ eq "ARRAY";
                     push @$_, $2;
                     $val = \$_->[-1];
                 }
             }
             else {
                 $val = \($headers->{$field_name} = $2);
             }
         }
         elsif ($line =~ /\A [\x09\x20]+ ([^\x0D\x0A]*)/x) {
             $val
               or die(qq/Unexpected header continuation line\n/);
             next unless length $1;
             $$val .= ' ' if length $$val;
             $$val .= $1;
         }
         elsif ($line =~ /\A \x0D?\x0A \z/x) {
            last;
         }
         else {
            die(q/Malformed header line: / . $Printable->($line) . "\n");
         }
    }
    return $headers;
}

sub write_request {
    @_ == 2 || die(q/Usage: $handle->write_request(request)/ . "\n");
    my($self, $request) = @_;
    $self->write_request_header(@{$request}{qw/method uri headers header_case/});
    $self->write_body($request) if $request->{cb};
    return;
}

# Standard request header names/case from HTTP/1.1 RFCs
my @rfc_request_headers = qw(
  Accept Accept-Charset Accept-Encoding Accept-Language Authorization
  Cache-Control Connection Content-Length Expect From Host
  If-Match If-Modified-Since If-None-Match If-Range If-Unmodified-Since
  Max-Forwards Pragma Proxy-Authorization Range Referer TE Trailer
  Transfer-Encoding Upgrade User-Agent Via
);

my @other_request_headers = qw(
  Content-Encoding Content-MD5 Content-Type Cookie DNT Date Origin
  X-XSS-Protection
);

my %HeaderCase = map { lc($_) => $_ } @rfc_request_headers, @other_request_headers;

# to avoid multiple small writes and hence nagle, you can pass the method line or anything else to
# combine writes.
sub write_header_lines {
    (@_ >= 2 && @_ <= 4 && ref $_[1] eq 'HASH') || die(q/Usage: $handle->write_header_lines(headers, [header_case, prefix])/ . "\n");
    my($self, $headers, $header_case, $prefix_data) = @_;
    $header_case ||= {};

    my $buf = (defined $prefix_data ? $prefix_data : '');

    # Per RFC, control fields should be listed first
    my %seen;
    for my $k ( qw/host cache-control expect max-forwards pragma range te/ ) {
        next unless exists $headers->{$k};
        $seen{$k}++;
        my $field_name = $HeaderCase{$k};
        my $v = $headers->{$k};
        for (ref $v eq 'ARRAY' ? @$v : $v) {
            $_ = '' unless defined $_;
            $buf .= "$field_name: $_\x0D\x0A";
        }
    }

    # Other headers sent in arbitrary order
    while (my ($k, $v) = each %$headers) {
        my $field_name = lc $k;
        next if $seen{$field_name};
        if (exists $HeaderCase{$field_name}) {
            $field_name = $HeaderCase{$field_name};
        }
        else {
            if (exists $header_case->{$field_name}) {
                $field_name = $header_case->{$field_name};
            }
            else {
                $field_name =~ s/\b(\w)/\u$1/g;
            }
            $field_name =~ /\A $Token+ \z/xo
              or die(q/Invalid HTTP header field name: / . $Printable->($field_name) . "\n");
            $HeaderCase{lc $field_name} = $field_name;
        }
        for (ref $v eq 'ARRAY' ? @$v : $v) {
            # unwrap a field value if pre-wrapped by user
            s/\x0D?\x0A\s+/ /g;
            die(qq/Invalid HTTP header field value ($field_name): / . $Printable->($_). "\n")
              unless $_ eq '' || /\A $Field_Content \z/xo;
            $_ = '' unless defined $_;
            $buf .= "$field_name: $_\x0D\x0A";
        }
    }
    $buf .= "\x0D\x0A";
    return $self->write($buf);
}

# return value indicates whether message length was defined; this is generally
# true unless there was no content-length header and we just read until EOF.
# Other message length errors are thrown as exceptions
sub read_body {
    @_ == 3 || die(q/Usage: $handle->read_body(callback, response)/ . "\n");
    my ($self, $cb, $response) = @_;
    my $te = $response->{headers}{'transfer-encoding'} || '';
    my $chunked = grep { /chunked/i } ( ref $te eq 'ARRAY' ? @$te : $te ) ;
    return $chunked
        ? $self->read_chunked_body($cb, $response)
        : $self->read_content_body($cb, $response);
}

sub write_body {
    @_ == 2 || die(q/Usage: $handle->write_body(request)/ . "\n");
    my ($self, $request) = @_;
    if ($request->{headers}{'content-length'}) {
        return $self->write_content_body($request);
    }
    else {
        return $self->write_chunked_body($request);
    }
}

sub read_content_body {
    @_ == 3 || @_ == 4 || die(q/Usage: $handle->read_content_body(callback, response, [read_length])/ . "\n");
    my ($self, $cb, $response, $content_length) = @_;
    $content_length ||= $response->{headers}{'content-length'};

    if ( defined $content_length ) {
        my $len = $content_length;
        while ($len > 0) {
            my $read = ($len > BUFSIZE) ? BUFSIZE : $len;
            $cb->($self->read($read, 0), $response);
            $len -= $read;
        }
        return length($self->{rbuf}) == 0;
    }

    my $chunk;
    $cb->($chunk, $response) while length( $chunk = $self->read(BUFSIZE, 1) );

    return;
}

sub write_content_body {
    @_ == 2 || die(q/Usage: $handle->write_content_body(request)/ . "\n");
    my ($self, $request) = @_;

    my ($len, $content_length) = (0, $request->{headers}{'content-length'});
    while () {
        my $data = $request->{cb}->();

        defined $data && length $data
          or last;

        if ( $] ge '5.008' ) {
            utf8::downgrade($data, 1)
                or die(qq/Wide character in write_content()\n/);
        }

        $len += $self->write($data);
    }

    $len == $content_length
      or die(qq/Content-Length mismatch (got: $len expected: $content_length)\n/);

    return $len;
}

sub read_chunked_body {
    @_ == 3 || die(q/Usage: $handle->read_chunked_body(callback, $response)/ . "\n");
    my ($self, $cb, $response) = @_;

    while () {
        my $head = $self->readline;

        $head =~ /\A ([A-Fa-f0-9]+)/x
          or die(q/Malformed chunk head: / . $Printable->($head) . "\n");

        my $len = hex($1)
          or last;

        $self->read_content_body($cb, $response, $len);

        $self->read(2) eq "\x0D\x0A"
          or die(qq/Malformed chunk: missing CRLF after chunk data\n/);
    }
    $self->read_header_lines($response->{headers});
    return 1;
}

sub write_chunked_body {
    @_ == 2 || die(q/Usage: $handle->write_chunked_body(request)/ . "\n");
    my ($self, $request) = @_;

    my $len = 0;
    while () {
        my $data = $request->{cb}->();

        defined $data && length $data
          or last;

        if ( $] ge '5.008' ) {
            utf8::downgrade($data, 1)
                or die(qq/Wide character in write_chunked_body()\n/);
        }

        $len += length $data;

        my $chunk  = sprintf '%X', length $data;
           $chunk .= "\x0D\x0A";
           $chunk .= $data;
           $chunk .= "\x0D\x0A";

        $self->write($chunk);
    }
    $self->write("0\x0D\x0A");
    if ( ref $request->{trailer_cb} eq 'CODE' ) {
        $self->write_header_lines($request->{trailer_cb}->())
    }
    else {
        $self->write("\x0D\x0A");
    }
    return $len;
}

sub read_response_header {
    @_ == 1 || die(q/Usage: $handle->read_response_header()/ . "\n");
    my ($self) = @_;

    my $line = $self->readline;

    $line =~ /\A (HTTP\/(0*\d+\.0*\d+)) [\x09\x20]+ ([0-9]{3}) [\x09\x20]+ ([^\x0D\x0A]*) \x0D?\x0A/x
      or die(q/Malformed Status-Line: / . $Printable->($line). "\n");

    my ($protocol, $version, $status, $reason) = ($1, $2, $3, $4);

    die (qq/Unsupported HTTP protocol: $protocol\n/)
        unless $version =~ /0*1\.0*[01]/;

    return {
        status       => $status,
        reason       => $reason,
        headers      => $self->read_header_lines,
        protocol     => $protocol,
    };
}

sub write_request_header {
    @_ == 5 || die(q/Usage: $handle->write_request_header(method, request_uri, headers, header_case)/ . "\n");
    my ($self, $method, $request_uri, $headers, $header_case) = @_;

    return $self->write_header_lines($headers, $header_case, "$method $request_uri HTTP/1.1\x0D\x0A");
}

sub _do_timeout {
    my ($self, $type, $timeout) = @_;
    $timeout = $self->{timeout}
        unless defined $timeout && $timeout >= 0;

    my $fd = fileno $self->{fh};
    defined $fd && $fd >= 0
      or die(qq/select(2): 'Bad file descriptor'\n/);

    my $initial = time;
    my $pending = $timeout;
    my $nfound;

    vec(my $fdset = '', $fd, 1) = 1;

    while () {
        $nfound = ($type eq 'read')
            ? select($fdset, undef, undef, $pending)
            : select(undef, $fdset, undef, $pending) ;
        if ($nfound == -1) {
            $! == EINTR
              or die(qq/select(2): '$!'\n/);
            redo if !$timeout || ($pending = $timeout - (time - $initial)) > 0;
            $nfound = 0;
        }
        last;
    }
    $! = 0;
    return $nfound;
}

sub can_read {
    @_ == 1 || @_ == 2 || die(q/Usage: $handle->can_read([timeout])/ . "\n");
    my $self = shift;
    if ( ref($self->{fh}) eq 'IO::Socket::SSL' ) {
        return 1 if $self->{fh}->pending;
    }
    return $self->_do_timeout('read', @_)
}

sub can_write {
    @_ == 1 || @_ == 2 || die(q/Usage: $handle->can_write([timeout])/ . "\n");
    my $self = shift;
    return $self->_do_timeout('write', @_)
}

sub _assert_ssl {
    my($ok, $reason) = HTTP::Tiny->can_ssl();
    die $reason unless $ok;
}

sub can_reuse {
    my ($self,$scheme,$host,$port,$peer) = @_;
    return 0 if
        $self->{pid} != $$
        || $self->{tid} != _get_tid()
        || length($self->{rbuf})
        || $scheme ne $self->{scheme}
        || $host ne $self->{host}
        || $port ne $self->{port}
        || $peer ne $self->{peer}
        || eval { $self->can_read(0) }
        || $@ ;
        return 1;
}

# Try to find a CA bundle to validate the SSL cert,
# prefer Mozilla::CA or fallback to a system file
sub _find_CA_file {
    my $self = shift();

    my $ca_file =
      defined( $self->{SSL_options}->{SSL_ca_file} )
      ? $self->{SSL_options}->{SSL_ca_file}
      : $ENV{SSL_CERT_FILE};

    if ( defined $ca_file ) {
        unless ( -r $ca_file ) {
            die qq/SSL_ca_file '$ca_file' not found or not readable\n/;
        }
        return $ca_file;
    }

    local @INC = @INC;
    pop @INC if $INC[-1] eq '.';
    return Mozilla::CA::SSL_ca_file()
        if eval { require Mozilla::CA; 1 };

    # cert list copied from golang src/crypto/x509/root_unix.go
    foreach my $ca_bundle (
        "/etc/ssl/certs/ca-certificates.crt",     # Debian/Ubuntu/Gentoo etc.
        "/etc/pki/tls/certs/ca-bundle.crt",       # Fedora/RHEL
        "/etc/ssl/ca-bundle.pem",                 # OpenSUSE
        "/etc/openssl/certs/ca-certificates.crt", # NetBSD
        "/etc/ssl/cert.pem",                      # OpenBSD
        "/usr/local/share/certs/ca-root-nss.crt", # FreeBSD/DragonFly
        "/etc/pki/tls/cacert.pem",                # OpenELEC
        "/etc/certs/ca-certificates.crt",         # Solaris 11.2+
    ) {
        return $ca_bundle if -e $ca_bundle;
    }

    die qq/Couldn't find a CA bundle with which to verify the SSL certificate.\n/
      . qq/Try installing Mozilla::CA from CPAN\n/;
}

# for thread safety, we need to know thread id if threads are loaded
sub _get_tid {
    no warnings 'reserved'; # for 'threads'
    return threads->can("tid") ? threads->tid : 0;
}

sub _ssl_args {
    my ($self, $host) = @_;

    my %ssl_args;

    # This test reimplements IO::Socket::SSL::can_client_sni(), which wasn't
    # added until IO::Socket::SSL 1.84
    if ( Net::SSLeay::OPENSSL_VERSION_NUMBER() >= 0x01000000 ) {
        $ssl_args{SSL_hostname} = $host,          # Sane SNI support
    }

    if ($self->{verify_SSL}) {
        $ssl_args{SSL_verifycn_scheme}  = 'http'; # enable CN validation
        $ssl_args{SSL_verifycn_name}    = $host;  # set validation hostname
        $ssl_args{SSL_verify_mode}      = 0x01;   # enable cert validation
        $ssl_args{SSL_ca_file}          = $self->_find_CA_file;
    }
    else {
        $ssl_args{SSL_verifycn_scheme}  = 'none'; # disable CN validation
        $ssl_args{SSL_verify_mode}      = 0x00;   # disable cert validation
    }

    # user options override settings from verify_SSL
    for my $k ( keys %{$self->{SSL_options}} ) {
        $ssl_args{$k} = $self->{SSL_options}{$k} if $k =~ m/^SSL_/;
    }

    return \%ssl_args;
}

1;
