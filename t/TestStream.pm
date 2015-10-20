package t::TestStream;

use 5.010001;
use Test::Nginx::Socket::Lua -Base;
use Test::Nginx::Util qw( $ServerPort $ServerAddr );

sub get_best_long_bracket_level ($);

my $port = $ENV{TEST_NGINX_STREAM_PORT} // ($ServerPort + 1);

add_block_preprocessor(sub {
    my ($block) = @_;

    my $name = $block->name;

    my $stream_config = $block->stream_config;
    my $stream_server_config = $block->stream_server_config;
    my $stream_req = $block->stream_request;

    if (defined $stream_server_config || defined $stream_config) {
        $stream_server_config //= '';
        $stream_config //= '';

        my $new_main_config = <<_EOC_;
stream {
$stream_config
    server {
        listen $port;

$stream_server_config
    }
}
_EOC_
        my $main_config = $block->main_config;
        if (defined $main_config) {
            $main_config .= $new_main_config;
        } else {
            $main_config = $new_main_config;
        }

        $block->set_value("main_config", $main_config);

        my $new_http_server_config = <<_EOC_;
            location = /t {
                content_by_lua_block {
                    local sock, err = ngx.socket.tcp()
                    assert(sock, err)

                    local ok, err = sock:connect("$ServerAddr", $port)
                    if not ok then
                        ngx.say("connect to stream server error: ", err)
                        return
                    end
_EOC_

        if (defined $stream_req) {
            my $level = get_best_long_bracket_level($stream_req);
            my $equals = "=" x $level;
            $new_http_server_config .= <<_EOC_;

                    local bytes, err = sock:send([$equals\[$stream_req\]$equals])
                    if not bytes then
                        ngx.say("send stream request error: ", err)
                        return
                    end
_EOC_
        }

        $new_http_server_config .= <<_EOC_;

                    local data, err = sock:receive("*a")
                    if not data then
                        ngx.say("receive stream response error: ", err)
                        return
                    end
_EOC_

        if (defined $block->response_body || defined $block->stream_response) {
            $new_http_server_config .= <<_EOC_;
                    ngx.print(data)
_EOC_
        }

        $new_http_server_config .= <<_EOC_;
                }
            }
_EOC_

        my $http_server_config = $block->config;
        if (defined $http_server_config) {
            $http_server_config .= $new_http_server_config;
        } else {
            $http_server_config = $new_http_server_config;
        }
        $block->set_value("config", $http_server_config);

        if (!defined $block->request) {
            $block->set_value("request", "GET /t\n");
        }
    }

    my $stream_response = $block->stream_response;
    if (defined $stream_response) {
        if (defined $block->response_body) {
            die "$name: conflicting response and response_body sections\n";
        }
        $block->set_value("response_body", $stream_response);
    }
});

sub get_best_long_bracket_level ($) {
    my ($s) = @_;

    my $equals = '';
    for (my $i = 0; $i < 100; $i++) {
        if ($s !~ /\[$equals\[|\]$equals\]/) {
            return $i;
        }

        my $equals .= "=";
    }

    die "failed to get the bets long bracket level\n";
}

1;
