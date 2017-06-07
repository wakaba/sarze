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
      my $Count = 0;

      sub main::psgi_app {
        return [200, [], [
          ref $_[0]->{'manakai.server.state'},
          defined $_[0]->{'manakai.server.state'}->background ? 1 : 0,
        ]];
      }

      package Worker;
      use Promised::Flow;

      sub start {
        my ($r, $s) = promised_cv;
        $Count++;
        return Promise->resolve (bless {
          stop => $s,
          completed => $r,
        }, $_[0]);
      }
      sub stop {
        $Count++;
        $_[0]->{stop}->();
      }
      sub completed {
        return $_[0]->{completed};
      }

      sub count { $Count }

      sub DESTROY ($) {
        local $@;
        eval { die };
        warn "Reference to @{[ref $_[0]]} is not discarded before global destruction\n"
            if $@ =~ /during global destruction/;
      } # DESTROY
    },
  )->then (sub {
    $server = $_[0];
    return $client1->request (path => []);
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->body_bytes, "Sarze::Worker::State0";
    } $c;
  });
} n => 1, name => 'no background class';

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
    worker_background_class => 'Worker',
    eval => q{
      my $Count = 0;

      sub main::psgi_app {
        return [200, [], [
          ref $_[0]->{'manakai.server.state'},
          ref $_[0]->{'manakai.server.state'}->background,
          $_[0]->{'manakai.server.state'}->background->count,
        ]];
      }

      package Worker;
      use Promised::Flow;

      sub start {
        my ($r, $s) = promised_cv;
        $Count++;
        return Promise->resolve (bless {
          stop => $s,
          completed => $r,
        }, $_[0]);
      }
      sub stop {
        $Count++;
        $_[0]->{stop}->();
      }
      sub completed {
        return $_[0]->{completed};
      }

      sub count { $Count }

      sub DESTROY ($) {
        local $@;
        eval { die };
        warn "Reference to @{[ref $_[0]]} is not discarded before global destruction\n"
            if $@ =~ /during global destruction/;
      } # DESTROY
    },
  )->then (sub {
    $server = $_[0];
    return $client1->request (path => []);
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->body_bytes, "Sarze::Worker::StateWorker1";
    } $c;
  });
} n => 1, name => 'has a background class';

run_tests;

=head1 LICENSE

Copyright 2016-2017 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
