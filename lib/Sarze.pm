package Sarze;
use strict;
use warnings;
our $VERSION = '1.0';
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::Fork;
use Promise;
use constant DEBUG => $ENV{WEBSERVER_DEBUG} || 0;

sub log ($$) {
  warn sprintf "%s: %s [%s]\n",
      $_[0]->{id}, $_[1], scalar gmtime time if DEBUG;
} # log

sub _create_worker ($$$) {
  my ($self, $fhs, $onstop) = @_;
  return if $self->{shutdowning};

  my $fork = $self->{forker}->fork;
  $fork->eval (q{srand});
  my $worker = $self->{workers}->{$fork} = {accepting => 1, shutdown => sub {}};
  for my $fh (@$fhs) {
    $fork->send_fh ($fh);
  }

  my $onnomore = sub {
    if ($worker->{accepting}) {
      delete $worker->{accepting};
      $onstop->();
    }
  }; # $onnomore

  my $completed;
  my $complete_p = Promise->new (sub { $completed = $_[0] });

  $fork->run ('Sarze::Worker::main', sub {
    my $fh = shift;
    my $rbuf = '';
    my $hdl; $hdl = AnyEvent::Handle->new
        (fh => $fh,
         on_read => sub {
           $rbuf .= $_[0]->{rbuf};
           $_[0]->{rbuf} = '';
           while ($rbuf =~ s/^([^\x0A]*)\x0A//) {
             my $line = $1;
             if ($line =~ /\Anomore\z/) {
               $onnomore->();
             } else {
               $self->log ("Broken command from worker process: |$line|");
             }
           }
         },
         on_error => sub {
           $_[0]->destroy;
           $onnomore->();
           $completed->();
           undef $hdl;
         },
         on_eof => sub {
           $_[0]->destroy;
           $onnomore->();
           $completed->();
           undef $hdl;
         });
    if ($self->{shutdowning}) {
      $hdl->push_write ("shutdown\x0A");
    } else {
      $hdl->push_write ("parent_id $self->{id}\x0A");
      $worker->{shutdown} = sub { $hdl->push_write ("shutdown\x0A") if $hdl };
    }
  });

  $self->{global_cv}->begin;
  $complete_p->then (sub {
    delete $worker->{shutdown};
    delete $self->{workers}->{$fork};
    undef $fork;
    $self->{global_cv}->end;
  });
} # _create_worker

sub _create_workers_if_necessary ($$) {
  my ($self, $fhs) = @_;
  my $count = 0;
  $count++ for grep { $_->{accepting} } values %{$self->{workers}};
  while ($count < $self->{max_worker_count} and not $self->{shutdowning}) {
    $self->_create_worker ($fhs, sub {
      $self->{timer} = AE::timer 1, 0, sub {
        $self->_create_workers_if_necessary ($fhs);
        delete $self->{timer};
      };
    });
    $count++;
  }
} # _create_workers_if_necessary

sub start ($%) {
  my ($class, %args) = @_;

  my $self = bless {
    workers => {},
    max_worker_count => $args{max_worker_count} || 3,
    global_cv => AE::cv,
    id => $$ . 'sarze' . ++$Sarze::N, # {id} can't contain \x0A
  }, $class;

  $self->{global_cv}->begin;
  $self->{shutdown} = sub {
    $self->{global_cv}->end;
    $self->{shutdown} = sub { };
    for (values %{$self->{workers}}) {
      $_->{shutdown}->();
    }
    delete $self->{signals};
    $self->{shutdowning}++;
  };

  for my $sig (qw(INT TERM QUIT)) {
    $self->{signals}->{$sig} = AE::signal $sig => sub {
      $self->log ("SIG$sig received");
      $self->{shutdown}->();
    };
  }
  for my $sig (qw(HUP)) {
    $self->{signals}->{$sig} = AE::signal $sig => sub {
      $self->log ("SIG$sig received");
      return if $self->{shutdowning};
      for (values %{$self->{workers}}) {
        $_->{shutdown}->();
      }
    };
    # XXX onhup hook
    # XXX recreate $fork
  }

  $self->{forker} = my $forker = AnyEvent::Fork->new;
  $forker->eval (q{
    use AnyEvent;
    $SIG{CHLD} = 'IGNORE';
  })->require ('Sarze::Worker');
  $forker->eval ($args{eval}) if defined $args{eval};
  if (defined $args{psgi_file_name}) {
    my $name = quotemeta $args{psgi_file_name};
    $forker->eval (q<
      my $code = do ">.$name.q<";
      die $@ if $@;
      unless (defined $code and ref $code eq 'CODE') {
        die "|>.$name.q<| does not return a CODE";
      }
      *main::psgi_app = $code;
    >);
  }
  $forker->send_arg ($args{connections_per_worker} || 1000);
  $forker->send_arg ($args{seconds_per_worker} || 60*10);
  $forker->send_arg (defined $args{worker_background_class} ? $args{worker_background_class} : '');
  my @fh;
  my @rstate;
  for (@{$args{hostports}}) {
    my ($h, $p) = @$_;
    AnyEvent::Socket::_tcp_bind ($h, $p, sub { # tcp_bind can't be used for unix domain socket :-<
      push @rstate, shift;
      $self->log ("Main bound: $h:$p");
      push @fh, $rstate[-1]->{fh};
    });
  }
  $self->_create_workers_if_necessary (\@fh);
  $self->{completed} = Promise->from_cv ($self->{global_cv})->then (sub {
    delete $self->{timer};
    @rstate = ();
    $self->log ("Main completed");
  });
  return Promise->resolve ($self);
} # start

sub stop ($) {
  $_[0]->{shutdown}->();
  return $_[0]->completed;
} # stop

sub completed ($) {
  return $_[0]->{completed};
} # completed

sub run ($@) {
  return shift->start (@_)->then (sub {
    return $_[0]->completed;
  });
} # run

sub DESTROY ($) {
  local $@;
  eval { die };
  warn "Reference to @{[ref $_[0]]} is not discarded before global destruction\
n"
      if $@ =~ /during global destruction/;
} # DESTROY

1;

=head1 LICENSE

Copyright 2016 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
