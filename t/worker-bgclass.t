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

  my $temp_path = get_temp_file_path;

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
      my $TempFile;

      sub main::psgi_app {
        my $temp_name = $_[0]->{HTTP_TEMP_FILE_NAME};
        if (defined $temp_name) {
          open $TempFile, '>', $temp_name or die "$temp_name: $!";
        }
        return [200, [], ['body']];
      }

      package Worker;
      use Promise;
      use Promised::Flow;
      sub start {
        my $ok;
        my $p = Promise->new (sub { $ok = $_[0] });
        return Promise->resolve (bless {
          completed => $p,
          done => $ok,
        }, $_[0]);
      }
      sub stop {
        my $done = $_[0]->{done};
        print $TempFile "stop\n" if defined $TempFile;
        promised_sleep (1)->then (sub {
          print $TempFile "stop sleeped\n" if defined $TempFile;
          $done->();
        });
      }
      sub completed {
        $_[0]->{completed};
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
    return Promise->all ([
      $client1->request (path => [], headers => {
        "temp-file-name" => $temp_path,
      }),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        is $res1->body_bytes, "body";
      } $c;
      return $server->stop;
    })->then (sub {
      test {
        is $temp_path->slurp, "stop\nstop sleeped\n";
      } $c;
    });
  });
} n => 2, name => 'has a background class';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::ConnectionClient->new_from_url ($url1);

  my $temp_path = get_temp_file_path;

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
      my $TempFile;

      sub main::psgi_app {
        my $temp_name = $_[0]->{HTTP_TEMP_FILE_NAME};
        if (defined $temp_name) {
          open $TempFile, '>', $temp_name or die "$temp_name: $!";
        }
        return [200, [], ['body']];
      }

      package Worker;
      use Promise;
      use Promised::Flow;
      sub start {
        my $ok;
        my $p = Promise->new (sub { $ok = $_[1] });
        return Promise->resolve (bless {
          completed => $p,
          done => $ok,
        }, $_[0]);
      }
      sub stop {
        my $done = $_[0]->{done};
        print $TempFile "stop\n" if defined $TempFile;
        promised_sleep (1)->then (sub {
          print $TempFile "stop sleeped\n" if defined $TempFile;
          $done->("stop");
        });
      }
      sub completed {
        $_[0]->{completed};
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
    return Promise->all ([
      $client1->request (path => [], headers => {
        "temp-file-name" => $temp_path,
      }),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        is $res1->body_bytes, "body";
      } $c;
      return $server->stop;
    })->then (sub {
      test {
        is $temp_path->slurp, "stop\nstop sleeped\n";
      } $c;
    });
  });
} n => 2, name => 'completed rejected';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::ConnectionClient->new_from_url ($url1);

  my $temp_path = get_temp_file_path;

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
      my $TempFile;

      sub main::psgi_app {
        my $temp_name = $_[0]->{HTTP_TEMP_FILE_NAME};
        if (defined $temp_name) {
          open $TempFile, '>', $temp_name or die "$temp_name: $!";
        }
        return [200, [], ['body']];
      }

      package Worker;
      use Promise;
      use Promised::Flow;
      sub start {
        my $ok;
        my $p = Promise->new (sub { $ok = $_[1] });
        return Promise->resolve (bless {
          completed => $p,
          done => $ok,
        }, $_[0]);
      }
      sub stop {
        die "stop throws";
      }
      sub completed {
        $_[0]->{completed};
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
    return Promise->all ([
      $client1->request (path => [], headers => {
        "temp-file-name" => $temp_path,
      }),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        is $res1->body_bytes, "body";
      } $c;
      return $server->stop;
    })->then (sub {
      test {
        is $temp_path->slurp, "";
      } $c;
    });
  });
} n => 2, name => 'thrown by stop';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::ConnectionClient->new_from_url ($url1);

  my $temp_path = get_temp_file_path;

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
      my $TempFile;

      sub main::psgi_app {
        my $temp_name = $_[0]->{HTTP_TEMP_FILE_NAME};
        if (defined $temp_name) {
          open $TempFile, '>', $temp_name or die "$temp_name: $!";
        }
        return [200, [], ['body']];
      }

      package Worker;
      use Promise;
      use Promised::Flow;
      sub start {
        die "start throws";
      }
      sub stop {
        die "stop throws";
      }
      sub completed {
        $_[0]->{completed};
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
    return Promise->all ([
      $client1->request (path => [], headers => {
        "temp-file-name" => $temp_path,
      }),
    ])->then (sub {
      my ($res1) = @{$_[0]};
      test {
        is $res1->body_bytes, "body";
      } $c;
      return $server->stop;
    })->then (sub {
      test {
        is $temp_path->slurp, "";
      } $c;
    });
  });
} n => 2, name => 'thrown by start';

run_tests;

=head1 LICENSE

Copyright 2016 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
