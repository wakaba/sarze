use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::ConnectionClient->new_from_url ($url1);

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
    });
  });
} n => 2, name => 'default max request body length';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::ConnectionClient->new_from_url ($url1);

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
    });
  });
} n => 2, name => 'max request body length specified';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::ConnectionClient->new_from_url ($url1);

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

run_tests;

=head1 LICENSE

Copyright 2016-2017 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
