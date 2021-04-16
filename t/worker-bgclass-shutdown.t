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
    worker_background_class => 'Worker',
    eval => q{
      use strict;
      use warnings;
      use Promised::Flow;
      my $TempFile;
      my $Count = 0;
      my $Stopped = 0;

      sub main::psgi_app {
        my $temp_name = $_[0]->{HTTP_TEMP_FILE_NAME};
        if (defined $temp_name and not defined $TempFile) {
          open $TempFile, '>', $temp_name or die "$temp_name: $!";
        }
        $Count++;
        return sub {
          my $ok = $_[0];
          (promised_wait_until { $Stopped })->then (sub {
            $Count++;
            $ok->([200, [], ['OK!']]);
          });
        };
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
        my $self = $_[0];
        $Count++;
        $Stopped = 1;
        return promised_sleep (1)->then (sub {
          $Count++;
          $self->{stop}->();
        });
      }
      sub completed {
        return $_[0]->{completed};
      }

      sub destroy {
        if (defined $TempFile) {
          print $TempFile $Count;
          close $TempFile;
        }
      }

      sub DESTROY ($) {
        local $@;
        eval { die };
        warn "$$: Reference to @{[ref $_[0]]} is not discarded before global destruction\n"
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
    return promised_wait_until {
      -f $temp_path and $temp_path->slurp;
     } timeout => 10;
  })->then (sub {
    test {
      is $temp_path->slurp, "23";
    } $c;
  });
} n => 1, name => 'destroy invoked after psgi and worker completion';

test {
  my $c = shift;
  my $host = '127.0.0.1';
  my $port1 = find_listenable_port;

  my $url1 = Web::URL->parse_string (qq<http://$host:$port1>);

  my @client;
  push @client, Web::Transport::ConnectionClient->new_from_url ($url1)
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
    worker_background_class => 'Worker',
    debug => 2,
    eval => q{
      use strict;
      use warnings;
      use Promised::Flow;
      my $TempFile;
      my $Count = 0;
      my $Stopped = 0;

      sub main::psgi_app {
        my $temp_name = $_[0]->{HTTP_TEMP_FILE_NAME};
        if (defined $temp_name and not defined $TempFile) {
          open $TempFile, '>', $temp_name or die "$temp_name: $!";
        }
        $Count++;
        return sub {
          my $ok = $_[0];
          (promised_wait_until { $Stopped })->then (sub {
            $Count++;
            $ok->([200, [], ['OK!']]);
          });
        };
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
        my $self = $_[0];
        warn "$$: Test: stop invoked";
        $Count++;
        $Stopped = 1;
        return promised_sleep (1)->then (sub {
          $Count++;
          warn "$$: Test: stop then invoked";
          $self->{stop}->();
        });
      }
      sub completed {
        return $_[0]->{completed};
      }

      sub destroy {
        warn "$$: Test: destroy invoked!";
        promised_sleep (1)->then (sub {
          warn "$$: Test: destroy then invoked!";
          if (defined $TempFile) {
            print $TempFile $Count;
            close $TempFile;
            warn qq{$$: Test: destroy "$TempFile" written!};
          }
        });
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
      promised_sleep (1)->then (sub {
        warn "$$: Test: stop server...";
        return $server->stop;
      }),
    ]);
  })->then (sub {
    warn "$$: Test: wait for temp...";
    return promised_wait_until { -f $temp_path and $temp_path->slurp } timeout => 30;
  })->then (sub {
    test {
      is $temp_path->slurp, "23";
    } $c;
  });
} n => 1, name => 'destroy invoked after psgi and worker completion';

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
        return [200, [], [$Count++]];
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

      sub destroy { die "destroy throws" }

      sub DESTROY ($) {
        local $@;
        eval { die };
        warn "$$: Reference to @{[ref $_[0]]} is not discarded before global destruction\n"
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
  });
} n => 1, name => 'destroy thrown';

run_tests;

=head1 LICENSE

Copyright 2016-2019 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
