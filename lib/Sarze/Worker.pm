package Sarze::Worker;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Handle;
use Promise;
use Promised::Flow;
use Web::Encoding;
use Web::Transport::PSGIServerConnection;

sub check {
  if ($Sarze::Worker::LoadError) {
    my $error = $Sarze::Worker::LoadError;
    $error =~ s/\x0A/\\x0A/g;
    print { $_[0] } encode_web_utf8 "globalfatalerror $$: $error\x0A";
  } else {
    print { $_[0] } "started\x0A";
  }
  close $_[0];
} # check

sub main {
  srand;
  my $wp = bless {%{$Sarze::Worker::Options},
                  shutdown_worker_background => sub { },
                  id => $$,
                  n => 0,
                  server_ws => []}, 'Sarze::Worker::Process';
  $wp->{parent_fh} = shift;
  $wp->{server_fhs} = [@_];

  my $cv = AE::cv;
  $cv->begin;
  $wp->{done} = sub { $cv->end };

  my $worker_timer;
  my $shutdown_timer;
  my $shutdown = sub {
    $wp->dont_accept_anymore;
    for (values %{$wp->{connections} or {}}) {
      $_->close_after_current_response;
    }
    delete $wp->{connections};
    delete $wp->{signals};
    $shutdown_timer = AE::timer $wp->{shutdown_timeout}, 0, sub {
      $cv->croak ("$wp->{id}: Shutdown timeout ($wp->{shutdown_timeout})\n");
      undef $shutdown_timer;
    };
    undef $worker_timer;
    $wp->{shutdown_worker_background}->();
  }; # $shutdown

  for my $sig (qw(INT TERM QUIT)) {
    $wp->{signals}->{$sig} = AE::signal $sig => sub {
      $wp->log ("SIG$sig received");
      $shutdown->();
    };
  }

  if ($wp->{seconds_per_worker} > 0) {
    my $timeout = $wp->{seconds_per_worker};
    if ($timeout >= 60*10) {
      $timeout += rand (60*5);
    } elsif ($timeout >= 60) {
      $timeout += rand 30;
    }
    $worker_timer = AE::timer $timeout, 0, sub {
      $wp->log ("|seconds_per_worker| elapsed ($timeout)");
      $shutdown->();
    };
  }

  $wp->{parent_handle} = AnyEvent::Handle->new
      (fh => $wp->{parent_fh},
       on_read => sub {
         while ($_[0]->{rbuf} =~ s/^([^\x0A]*)\x0A//) {
           my $line = $1;
           if ($line =~ /\Ashutdown\z/) {
             $shutdown->();
           } elsif ($line =~ s/^parent_id //) {
             $wp->{id} = $line . '.' . $$;
             $wp->log ("Worker started");
           } else {
             $wp->log ("Broken command from main process: |$line|");
           }
         }
       },
       on_eof => sub { $_[0]->destroy },
       on_error => sub { $_[0]->destroy });
  # XXX should run $shutdown when connection is closed

  my $p = Promise->from_cv ($cv);
  if (defined $wp->{worker_background_class}) {
    my $q = Promise->resolve->then (sub {
      return $wp->{worker_background_class}->start;
    })->then (sub {
      my $obj = $_[0]; # should be an object but might not ...
      my ($ok, $ng);
      my $p = Promise->new (sub { ($ok, $ng) = @_ });
      $wp->{shutdown_worker_background} = sub {
        $wp->{shutdown_worker_background} = sub { };
        Promise->resolve->then (sub {
          return $obj->stop; # might return any value or throw
        })->catch (sub {
          $ng->($_[0]);
        });
      };
      Promise->resolve->then (sub {
        return $obj->completed;
      })->then (sub { $ok->() }, sub { $ng->($_[0]) });
      return $p;
    })->catch (sub {
      warn $_[0]; # XXX report to main process
    })->then ($shutdown);
    $p = $p->then (sub { return $q });
  }

  for my $fh (@{$wp->{server_fhs}}) {
    push @{$wp->{server_ws}}, AE::io $fh, 0, sub {
      while (1) {
        $cv->begin;
        my ($args, $n) = $wp->accept_next ($fh);
        unless (defined $args) {
          $cv->end;
          last;
        }

        my $con = Web::Transport::PSGIServerConnection
            ->new_from_app_and_ae_tcp_server_args
                (\&main::psgi_app, $args, parent_id => $wp->{id});
        $con->max_request_body_length ($wp->{max_request_body_length})
            if defined $wp->{max_request_body_length};
        $wp->{connections}->{$con} = $con;
        promised_cleanup {
          $wp->log (sprintf "Connection completed (%s)", $con->id);
          $cv->end;
          delete $wp->{connections}->{$con};
        } $con->completed;
      }
    };
  } # $fh

  $p->to_cv->recv; # main loop
  undef $shutdown_timer;

  $wp->log ("Worker completed");
  close $wp->{parent_fh};
  undef $wp;
} # main

package Sarze::Worker::Process;
use constant DEBUG => $ENV{WEBSERVER_DEBUG} || 0;
use Web::Encoding;

sub log ($$) {
  warn encode_web_utf8 sprintf "%s: %s [%s]\n",
      $_[0]->{id}, $_[1], scalar gmtime time if DEBUG;
} # log

sub accept_next ($$) {
  my ($self, $s_fh) = @_;

  return (undef, undef) unless defined $self->{server_ws};
  my $peer = accept (my $fh, $s_fh);
  return (undef, undef) unless $peer;

  AnyEvent::fh_unblock $fh;
  my ($service, $host) = AnyEvent::Socket::unpack_sockaddr $peer;
  my $args = [$fh, AnyEvent::Socket::format_address $host, $service];

  my $n = $self->{n}++;
  $self->log ("Accepted $args->[1]:$args->[2] (connection #$n)");

  $self->dont_accept_anymore if $self->{connections_per_worker} <= $self->{n};

  return ($args, $n);
} # accept_next

sub dont_accept_anymore ($) {
  my $self = $_[0];
  return if $self->{nomore}++;

  $self->{parent_handle}->push_write ("nomore\x0A");

  delete $self->{server_ws};
  for (@{delete $self->{server_fhs}}) {
    close $_;
  }

  $self->{done}->();

  $self->log ("Worker closed");
} # dont_accept_anymore

sub DESTROY ($) {
  local $@;
  eval { die };
  warn "Reference to @{[ref $_[0]]} is not discarded before global destruction\n"
      if $@ =~ /during global destruction/;
} # DESTROY

1;

=head1 LICENSE

Copyright 2016-2017 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
