package Sarze::Worker;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Handle;
use Promise;
use Web::Transport::PSGIServerConnection;

sub main {
  my $wp = bless {shutdown_timeout => 10,
                  id => $$,
                  n => 0,
                  server_ws => []}, 'Sarze::Worker::Process';
  $wp->{parent_fh} = shift;
  $wp->{connections_per_worker} = shift;
  $wp->{seconds_per_worker} = shift;
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
  }; # $shutdown

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

  for my $fh (@{$wp->{server_fhs}}) {
warn "y";
    push @{$wp->{server_ws}}, AE::io $fh, 0, sub {
warn "x";
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
        $wp->{connections}->{$con} = $con;
        $con->completed->then (sub {
          $wp->log (sprintf "Connection completed (%s)", $con->id);
          $cv->end;
          delete $wp->{connections}->{$con};
        });
      }
    };
  } # $fh

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

  $cv->recv; # main loop
  undef $shutdown_timer;

  $wp->log ("Worker completed");
  close $wp->{parent_fh};
  undef $wp;
} # main

package Sarze::Worker::Process;
use constant DEBUG => $ENV{WEBSERVER_DEBUG} || 0;

sub log ($$) {
  warn sprintf "%s: %s [%s]\n",
      $_[0]->{id}, $_[1], scalar gmtime time if DEBUG;
} # log

sub accept_next ($$) {
  my ($self, $s_fh) = @_;

  return (undef, undef) unless defined $self->{server_ws};
warn "accept";
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

Copyright 2016 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
