use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;
use Promised::Command;

for my $signal (qw(TERM INT QUIT)) {
test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port>);
  my $client1 = Web::Transport::ConnectionClient->new_from_url ($url1);
  my $client2 = Web::Transport::ConnectionClient->new_from_url ($url1);

  my $cmd = Promised::Command->new (['perl', '-e', q{
    use Sarze;
    my $host = shift;
    my $port = shift;
    my $p = Sarze->run (
      hostports => [
        [$host, $port],
      ],
      eval => q{
        sub main::psgi_app {
          return [200, [], ['OK!']];
        }
      },
    );
    syswrite STDOUT, "started\x0A";
    $p->to_cv->recv;
  }, $host, $port]);
  $cmd->stdout (\(my $stdout = ''));

  promised_cleanup {
    return Promise->all ([
      $cmd->wait,
      $client1->close,
      $client2->close,
    ])->then (sub { done $c; undef $c });
  } $cmd->run->then (sub {
    return promised_wait_until {
      return $stdout =~ /started/;
    } timeout => 30;
  })->then (sub {
    return $client1->request (path => []);
  })->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->body_bytes, 'OK!';
    } $c;
    return $cmd->send_signal ($signal);
  })->then (sub {
    return promised_sleep 1;
  })->then (sub {
    return $client2->request (path => []);
  })->then (sub {
    my $res = $_[0];
    test {
      ok $res->is_network_error, $res;
    } $c;
  });
} n => 3, name => $signal;
}

run_tests;

=head1 LICENSE

Copyright 2016-2017 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
