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

  my @client;
  push @client, Web::Transport::ConnectionClient->new_from_url ($url1)
      for 1..20;

  my $server;
  promised_cleanup {
    return Promise->all ([
      (defined $server ? $server->stop : undef),
      map { $_->close } @client,
    ])->then (sub { done $c; undef $c });
  } Sarze->start (
    hostports => [
      [$host, $port1],
    ],
    eval => q{
      sub main::psgi_app {
        return [200, [], [rand]];
      }
    },
  )->then (sub {
    $server = $_[0];
    return Promise->all ([map {
      $_->request (path => []);
    } @client]);
  })->then (sub {
    my @res = @{$_[0]};
    test {
      my $results = {};
      for (@res) {
        $results->{$_->body_bytes}++;
      }
      note join "\n", %$results;
      ok ! grep { $_ > 1 } values %$results;
    } $c;
  });
} n => 1, name => 'rand values';

run_tests;

=head1 LICENSE

Copyright 2016-2017 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
