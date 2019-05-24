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
    worker_state_class => 'Worker',
    eval => q{
      my $TempFile;

      sub main::psgi_app {
        my $temp_name = $_[0]->{HTTP_TEMP_FILE_NAME};
        if (defined $temp_name) {
          open $TempFile, '>', $temp_name or die "$temp_name: $!";
          print $TempFile defined $_[0]->{'manakai.server.state'}->data->{params} ? 1 : 0, "\n";
        }
        return [200, [], ['body']];
      }

      package Worker;
      use Promise;
      use Promised::Flow;
      sub start {
        my ($class, %args) = @_;
        my ($r, $s) = promised_cv;
        $args{signal}->manakai_onabort (sub {
          print $TempFile "stop\n" if defined $TempFile;
          return promised_sleep (1)->then (sub {
            print $TempFile "stop sleeped\n" if defined $TempFile;
            $s->();
          });
        });
        return Promise->resolve ([(bless {params => $args{params}}, $class), $r]);
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
      return promised_sleep 1;
    })->then (sub {
      test {
        is $temp_path->slurp, "0\nstop\nstop sleeped\n";
      } $c;
    });
  });
} n => 2, name => 'has a class';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::BasicClient->new_from_url ($url1);

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
    worker_state_class => 'Worker',
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
        my ($class, %args) = @_;
        my ($r, $s) = promised_cv;
        $args{signal}->manakai_onabort (sub {
          print $TempFile "stop\n" if defined $TempFile;
          return promised_sleep (1)->then (sub {
            print $TempFile "stop sleeped\n" if defined $TempFile;
            close $TempFile if defined $TempFile;
            $s->(Promise->reject ("stop"));
          });
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
  my $client1 = Web::Transport::BasicClient->new_from_url ($url1);

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
    worker_state_class => 'Worker',
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
        my ($class, %args) = @_;
        my ($r, $s) = promised_cv;
        $args{signal}->manakai_onabort (sub {
          $s->();
          die "stop throws";
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
  my $client1 = Web::Transport::BasicClient->new_from_url ($url1, {
    last_resort_timeout => 2,
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
    worker_state_class => 'Worker',
    eval => q{
      sub main::psgi_app {
        return [200, [], ['body']];
      }

      package Worker;
      use Promise;
      use Promised::Flow;
      sub start {
        die "start throws";
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
    return $client1->request (path => [])->then (sub { test { ok 0 } $c }, sub {
      my ($res1) = $_[0];
      test {
        ok $res1->is_network_error;
      } $c;
      return $server->stop;
    });
  });
} n => 1, name => 'thrown by start';

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
    max_worker_count => 1,
    worker_state_class => 'Worker',
    eval => q{
      my $Stop;
      sub main::psgi_app {
        $Stop->() if defined $Stop;
        return [200, [], [$$]];
      }

      package Worker;
      use Promise;
      use Promised::Flow;
      sub start {
        my ($class, %args) = @_;
        my ($r, $s) = promised_cv;
        $Stop = $s;
        return Promise->resolve ([(bless {}, $class), $r]);
      }
      sub DESTROY ($) {
        undef $Stop;
        local $@;
        eval { die };
        warn "Reference to @{[ref $_[0]]} is not discarded before global destruction\n"
            if $@ =~ /during global destruction/;
      } # DESTROY
    },
  )->then (sub {
    $server = $_[0];
    my $p1;
    return $client1->request (path => [])->then (sub {
      my ($res1) = $_[0];
      test {
        is $res1->status, 200;
        $p1 = $res1->body_bytes;
      } $c;
      return $client1->request (path => []);
    })->then (sub {
      my ($res2) = $_[0];
      test {
        is $res2->status, 200;
        is $res2->body_bytes, $p1;
      } $c;
    });
  })->then (sub {
    return $server->stop;
  });
} n => 3, name => 'early resolution does not change the result';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);
  my $client1 = Web::Transport::BasicClient->new_from_url ($url1);

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
    worker_state_class => 'Worker',
    worker_state_params => {
      "abc" => "\x{FE00}",
    },
    eval => q{
      my $TempFile;

      sub main::psgi_app {
        my $temp_name = $_[0]->{HTTP_TEMP_FILE_NAME};
        if (defined $temp_name) {
          open $TempFile, '>:encoding(utf-8)', $temp_name or die "$temp_name: $!";
          print $TempFile $_[0]->{'manakai.server.state'}->data->{params}->{abc}, "\n";
        }
        return [200, [], ['body']];
      }

      package Worker;
      use Promise;
      use Promised::Flow;
      sub start {
        my ($class, %args) = @_;
        my ($r, $s) = promised_cv;
        $args{signal}->manakai_onabort (sub {
          print $TempFile "stop\n" if defined $TempFile;
          return promised_sleep (1)->then (sub {
            print $TempFile "stop sleeped\n" if defined $TempFile;
            $s->();
          });
        });
        return Promise->resolve ([(bless {params => $args{params}}, $class), $r]);
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
      return promised_sleep 1;
    })->then (sub {
      test {
        is $temp_path->slurp, "\xEF\xB8\x80\nstop\nstop sleeped\n";
      } $c;
    });
  });
} n => 2, name => 'params';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);

  my @client;
  push @client, Web::Transport::BasicClient->new_from_url ($url1)
      for 1..10;

  my $temp_path = get_temp_file_path;
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
    max_worker_count => 1,
    worker_state_class => 'Worker',
    eval => q{
      use strict;
      use warnings;
      use Promised::Flow;
      my $TempFile;
      my $Count = 0;

      sub main::psgi_app {
        my $temp_name = $_[0]->{HTTP_TEMP_FILE_NAME};
        if (defined $temp_name and not defined $TempFile) {
          open $TempFile, '>', $temp_name or die "$temp_name: $!";
        }
        $Count++;
        return sub {
          my $ok = $_[0];
          $Count++;
          return promised_sleep (3)->then (sub {
            $ok->([200, [], ['OK!']]);
          });
        };
      }

      package Worker;
      use Promised::Flow;

      sub start {
        my ($class, %args) = @_;
        $Count++;
        my ($r, $s) = promised_cv;
        $args{signal}->manakai_onabort (sub {
          $Count++;
          if (defined $TempFile) {
            print $TempFile $Count;
            close $TempFile;
          }
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
    my @req = map { $_->request (path => [], headers => {
      "temp-file-name" => $temp_path,
    }) } @client;
    return Promise->all ([
      @req, # after requests are sent (but not received response), stop server
      promised_sleep (1)->then (sub { $server->stop }),
    ]);
  })->then (sub {
    return promised_wait_until { $temp_path->slurp } timeout => 10;
  })->then (sub {
    test {
      is $temp_path->slurp, "22";
    } $c;
  });
} n => 1, name => 'destroy invoked after psgi and worker completion';

run_tests;

=head1 LICENSE

Copyright 2016-2019 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
