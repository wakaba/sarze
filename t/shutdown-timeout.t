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
    seconds_per_worker => .5,
    shutdown_timeout => .5,
    eval => q{
      use Promised::Flow;
      sub main::psgi_app {
        my $env = $_[0];
        return sub {
          my $r = $_[0];
          promised_sleep (2)->then (sub {
            $r->([200, [], ['abcde']]);
          });
        };
      }
    },
  )->then (sub {
    $server = $_[0];
    return Promise->all ([
      $client1->request (path => []),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        ok $res1->is_network_error, $res1;
      } $c;
    });
  });
} n => 1, name => 'response stop by shutdown timeout';

run_tests;

=head1 LICENSE

Copyright 2016 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
