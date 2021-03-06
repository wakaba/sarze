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
        return [200, [], [$_[0]->{HTTP_HOST}]];
      }
    },
  )->then (sub {
    $server = $_[0];
    return Promise->all ([
      $client1->request (path => []),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        is $res1->body_bytes, "$host:$port1";
      } $c;
    });
  });
} n => 1, name => 'tcp';

{
  package test::UnixProxyManager;
  sub get_proxies_for_url {
    return Promise->resolve ([{protocol => 'unix', path => $_[0]->[0]}]);
  }
}

test {
  my $c = shift;
  my $temp_path = get_temp_file_path;

  my $url1 = Web::URL->parse_string (qq<http://hoge.test>);
  my $client1 = Web::Transport::ConnectionClient->new_from_url ($url1);

  my $pm = bless [$temp_path], 'test::UnixProxyManager';
  $client1->proxy_manager ($pm);

  my $server;
  promised_cleanup {
    return Promise->all ([
      (defined $server ? $server->stop : undef),
      $client1->close,
    ])->then (sub { done $c; undef $c });
  } Sarze->start (
    hostports => [
      ['unix/', $temp_path->stringify],
    ],
    eval => q{
      sub main::psgi_app {
        return [200, [], [$_[0]->{HTTP_HOST}]];
      }
    },
  )->then (sub {
    $server = $_[0];
    return Promise->all ([
      $client1->request (path => []),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        is $res1->body_bytes, "hoge.test";
      } $c;
    });
  });
} n => 1, name => 'unix';

run_tests;

=head1 LICENSE

Copyright 2016 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
