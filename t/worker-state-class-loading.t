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
    worker_state_class => 'Worker',
    max_worker_count => 1,
    eval => q{
      my $Count = 0;

      sub main::psgi_app {
        return [200, [], [$Count]];
      }

      package Worker;
      use Promised::Flow;

      sub start {
        my ($class, %args) = @_;
        $Count++;
        my ($r, $s) = promised_cv;
        $args{signal}->manakai_onabort (sub {
          $Count++;
          $s->();
        });
        return Promise->resolve ([(bless {}, $class), $r]);
      }
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
      is $res->body_bytes, "1";
    } $c;
    return $client1->request (path => []);
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->body_bytes, "1";
    } $c;
  });
} n => 2, name => 'has a state class';

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
    worker_state_class => 'Worker',
    eval => q{
      sub main::psgi_app {
        return [200, [], ['123']];
      }

      package Worker;
      use Promised::Flow;
      sub DESTROY ($) {
        local $@;
        eval { die };
        warn "Reference to @{[ref $_[0]]} is not discarded before global destruction\n"
            if $@ =~ /during global destruction/;
      } # DESTROY
    },
  )->then (sub {
    $server = $_[0];
    test {
      ok 0;
    } $c;
  }, sub {
    my $error = $_[0];
    test {
      like $error, qr{Worker->start is not defined};
    } $c;
  })->then (sub {
    return $client1->request (path => []);
  })->then (sub { test { ok 0 } $c }, sub {
    my $res = $_[0];
    test {
      ok $res->is_network_error;
    } $c;
  });
} n => 2, name => 'no start method';

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
    worker_state_class => 'ab cd ef',
    eval => q{
      sub main::psgi_app {
        return [200, [], ['123']];
      }
    },
  )->then (sub {
    $server = $_[0];
    test {
      ok 0;
    } $c;
  }, sub {
    my $error = $_[0];
    test {
      like $error, qr{ab cd ef->start is not defined};
    } $c;
  })->then (sub {
    return $client1->request (path => []);
  })->then (sub { test { ok 0 } $c }, sub {
    my $res = $_[0];
    test {
      ok $res->is_network_error;
    } $c;
  });
} n => 2, name => 'Bad background class name';

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
    worker_state_class => 'Foo::Bar',
    eval => q{
      sub main::psgi_app {
        return [200, [], ['123']];
      }
    },
  )->then (sub {
    $server = $_[0];
    test {
      ok 0;
    } $c;
  }, sub {
    my $error = $_[0];
    test {
      like $error, qr{Foo::Bar->start is not defined};
    } $c;
  })->then (sub {
    return $client1->request (path => []);
  })->then (sub { test { ok 0 } $c }, sub {
    my $res = $_[0];
    test {
      ok $res->is_network_error;
    } $c;
  });
} n => 2, name => 'Undefined background class name';

run_tests;

=head1 LICENSE

Copyright 2016-2019 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
