package Sarze::Worker;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Handle;
use Promise;
use Web::Transport::PSGIServerConnection;

sub main () {
  my $wp = bless {parent_fh => $_[0],
                  server_fh => $_[3],
                  connections_per_worker => $_[1],
                  seconds_per_worker => $_[2],
                  shutdown_timeout => 10,
                  id => $$,
                  n => 0}, 'Sarze::Worker::Process';

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

  my $rbuf = '';
  $wp->{parent_handle} = AnyEvent::Handle->new
      (fh => $wp->{parent_fh},
       on_read => sub {
         $rbuf .= $_[0]->{rbuf};
         $_[0]->{rbuf} = '';
         while ($rbuf =~ s/^([^\x0A]*)\x0A//) {
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

  $wp->{server_w} = AE::io $wp->{server_fh}, 0, sub {
    while (1) {
      $cv->begin;
      my ($args, $n) = $wp->accept_next;
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

sub accept_next ($) {
  my $self = $_[0];

  return (undef, undef) unless defined $self->{server_fh};
  my $peer = accept my $fh, $self->{server_fh};
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

  delete $self->{server_w};
  close $self->{server_fh};
  delete $self->{server_fh};

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
