use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;
use Web::Transport::BasicClient;

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::BasicClient->new_from_url ($url1, {
    debug => 1,
  });

  my $server;
  promised_cleanup {
    return Promise->all ([
      (defined $server ? $server->stop : undef),
      $client1->close,
    ])->then (sub { done $c; undef $c });
  } Sarze->start (
    hostports => [
      [$host, $port1],
    ],
    eval => q{
      sub main::psgi_app {
        return [200, [], ['OK!']];
      }
    },
    debug => 1,
  )->then (sub {
    $server = $_[0];
    return Promise->all ([
      $client1->request (path => [], body => 'x' x (500*1024*1024)),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        is $res1->status, 413;
        is $res1->body_bytes, '413';
      } $c;
    }, sub {
      my $e = $_[0];
      test {
        ok $e->is_network_error, $e;
        ok $^O eq 'darwin';
        #88323.1.1h1.1: S: Content-Length: 524288000\x0D
        #88323.1.1h1.1: S: \x0D
        #88323.1.1h1.1: S: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx... (524288000)
        #88323.1.1h1: S: EOF (Perl I/O error: Protocol wrong type for socket at t/max-request.t line 50.\x0A)
        #88323.1.1: TCP: closed
        #88323.1.1h1: R: EOF (Perl I/O error: Protocol wrong type for socket at t/max-request.t line 50.\x0A)
        #88323.1.1h1: endstream 88323.1.1h1.1 Fri May 24 05:35:09 2019
        #88323.1.1h1: ========== Web::Transport::HTTPStream::ClientConnection
      } $c;
    });
  });
} n => 2, name => 'default max request body length';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::BasicClient->new_from_url ($url1);

  my $server;
  promised_cleanup {
    return Promise->all ([
      (defined $server ? $server->stop : undef),
      $client1->close,
    ])->then (sub { done $c; undef $c });
  } Sarze->start (
    hostports => [
      [$host, $port1],
    ],
    eval => q{
      sub main::psgi_app {
        return [200, [], ['OK!']];
      }
    },
    max_request_body_length => 500*1024-1,
  )->then (sub {
    $server = $_[0];
    return Promise->all ([
      $client1->request (path => [], body => 'x' x (500*1024)),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        is $res1->status, 413;
        is $res1->body_bytes, '413';
      } $c;
    }, sub {
      my $e = $_[0];
      test {
        ok $e->is_network_error, $e;
        ok $^O eq 'darwin';
      } $c;
    });
  });
} n => 2, name => 'max request body length specified';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::BasicClient->new_from_url ($url1);

  my $server;
  promised_cleanup {
    return Promise->all ([
      (defined $server ? $server->stop : undef),
      $client1->close,
    ])->then (sub { done $c; undef $c });
  } Sarze->start (
    hostports => [
      [$host, $port1],
    ],
    eval => q{
      sub main::psgi_app {
        return [200, [], ['OK!']];
      }
    },
    max_request_body_length => 500*1024+1,
  )->then (sub {
    $server = $_[0];
    return Promise->all ([
      $client1->request (path => [], body => 'x' x (500*1024)),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        is $res1->status, 200;
        is $res1->body_bytes, 'OK!';
      } $c;
    });
  });
} n => 2, name => 'max request body length specified';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::BasicClient->new_from_url ($url1);

  my $server;
  promised_cleanup {
    return Promise->all ([
      (defined $server ? $server->stop : undef),
      $client1->close,
    ])->then (sub { done $c; undef $c });
  } Sarze->start (
    hostports => [
      [$host, $port1],
    ],
    eval => q{
      sub main::psgi_app {
        return [200, [], ['OK!']];
      }
    },
    max_request_body_length => 1,
  )->then (sub {
    $server = $_[0];
    return Promise->all ([
      $client1->request (path => [], body => 'xy'),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        is $res1->status, 413;
        is $res1->body_bytes, '413';
      } $c;
    });
  });
} n => 2, name => 'max request body length specified';

run_tests;

=head1 LICENSE

Copyright 2016-2017 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
