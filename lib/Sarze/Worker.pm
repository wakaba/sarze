package Sarze::Worker;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Handle;
use Promise;
use Web::Transport::PSGIServerConnection;

sub main () {
  my $wp = bless {parent_fh => $_[0],
                  server_fh => $_[2],
                  connection_per_worker => $_[1],
                  id => $$,
                  n => 0}, 'Sarze::Worker::Process';

  my $cv = AE::cv;
  $cv->begin;
  $wp->{done} = sub { $cv->end };

  my $rbuf = '';
  $wp->{parent_handle} = AnyEvent::Handle->new
      (fh => $wp->{parent_fh},
       on_read => sub {
         $rbuf .= $_[0]->{rbuf};
         $_[0]->{rbuf} = '';
         while ($rbuf =~ s/^([^\x0A]*)\x0A//) {
           my $line = $1;
           if ($line =~ /\Ashutdown\z/) {
             $wp->dont_accept_anymore;
             delete $wp->{signals};
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
      $con->completed->then (sub {
        $wp->log ("Connection completed ($n of $wp->{connection_per_worker})");
        $cv->end;
      });
    }
  };

  for my $sig (qw(INT TERM QUIT)) {
    $wp->{signals}->{$sig} = AE::signal $sig => sub {
      $wp->log ("SIG$sig received");
      $wp->dont_accept_anymore;
      delete $wp->{signals};
    };
  }

  $cv->recv; # main loop

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

  $self->dont_accept_anymore if $self->{connection_per_worker} <= $self->{n};

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
