package Sarze;
use strict;
use warnings;
our $VERSION = '1.0';
use Carp;
use Data::Dumper;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::Fork;
use Promise;
use Web::Encoding;
use constant DEBUG => $ENV{WEBSERVER_DEBUG} || 0;

sub log ($$) {
  warn encode_web_utf8 sprintf "%s: %s [%s]\n",
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

  my ($start_ok, $start_ng) = @_;
  my $start_p = Promise->new (sub { ($start_ok, $start_ng) = @_ });

  my $onnomore = sub {
    if ($worker->{accepting}) {
      delete $worker->{accepting};
      $onstop->();
    }
#    $start_ng->($self->{globalfatalerror} || "Aborted before start of child"); # XXX
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
warn "$fork $_[0] [[$self->{id} $rbuf]]";
           $_[0]->{rbuf} = '';
           while ($rbuf =~ s/^([^\x0A]*)\x0A//) {
             my $line = $1;
             if ($line eq 'nomore') {
               $onnomore->();
             } elsif ($line eq 'started') {
               $start_ok->();
             } elsif ($line =~ /\Aglobalfatalerror (.*)\z/s) {
               my $error = "Fatal error: " . decode_web_utf8 $1;
               $self->{globalfatalerror} ||= $error;
               $self->log ($error);
               $start_ng->($error);
               $self->{shutdown}->();
             } else {
               $self->log ("Broken command from worker process: |$line|");
             }
           }
         },
         on_error => sub {
           $_[0]->destroy;
warn "$fork $_[0] [[$self->{id} onerror $_[2]]]";
           $onnomore->();
           $completed->();
           undef $hdl;
         },
         on_eof => sub {
           $_[0]->destroy;
warn "$fork $_[0] [[$self->{id} oneof $_[2]]]";
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

  return $start_p;
} # _create_worker

sub _create_workers_if_necessary ($$) {
  my ($self, $fhs) = @_;
  my $p = [];
  my $count = 0;
  $count++ for grep { $_->{accepting} } values %{$self->{workers}};
  while ($count < $self->{max_worker_count} and not $self->{shutdowning}) {
    push @$p, $self->_create_worker ($fhs, sub {
      $self->{timer} = AE::timer 1, 0, sub {
        $self->_create_workers_if_necessary ($fhs);
        delete $self->{timer};
      };
    });
    $count++;
  }
  return Promise->all ($p);
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
  if (defined $args{eval}) {
    my $c = sub { scalar Carp::caller_info
        (Carp::short_error_loc() || Carp::long_error_loc()) }->();
    $c->{file} =~ tr/\x0D\x0A"/   /;
    my $line = sprintf qq{\n#line 1 "Sarze eval (%s line %d)"\n}, $c->{file}, $c->{line};
    $forker->eval (sprintf q{
      eval "%s";
      if ($@) {
        $Sarze::Worker::LoadError = "$@";
      } elsif (not defined &main::psgi_app) {
        $Sarze::Worker::LoadError = "%s does not define &main::psgi_app";
      }
    }, quotemeta ($line.$args{eval}), quotemeta sprintf "Sarze eval (%s line %d)", $c->{file}, $c->{line});
  }
  if (defined $args{psgi_file_name}) {
    require Cwd;
    my $name = quotemeta Cwd::abs_path ($args{psgi_file_name});
    $forker->eval (q<
      my $name = ">.$name.q<";
      my $code = do $name;
      if ($@) {
        $Sarze::Worker::LoadError = "$name: $@";
      } elsif (defined $code) {
        if (ref $code eq 'CODE') {
          *main::psgi_app = $code;
        } else {
          $Sarze::Worker::LoadError = "|$name| does not return a CODE";
        }
      } else {
        if ($!) {
          $Sarze::Worker::LoadError = "$name: $!";
        } else {
          $Sarze::Worker::LoadError = "|$name| does not return a CODE";
        }
      }
    >);
  }
  my $options = Dumper {
    connections_per_worker => $args{connections_per_worker} || 1000,
    seconds_per_worker => $args{seconds_per_worker} || 60*10,
    shutdown_timeout => $args{shutdown_timeout} || 60*1,
    worker_background_class => defined $args{worker_background_class} ? $args{worker_background_class} : '',
    max_request_body_length => $args{max_request_body_length},
  };
  $options =~ s/^\$VAR1 = //;
  $forker->send_arg ($options);
  my @fh;
  my @rstate;
  for (@{$args{hostports}}) {
    my ($h, $p) = @$_;
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;
    eval {
      AnyEvent::Socket::_tcp_bind ($h, $p, sub { # tcp_bind can't be used for unix domain socket :-<
        push @rstate, shift;
        $self->log ("Main bound: $h:$p");
        push @fh, $rstate[-1]->{fh};
      });
    };
    if ($@) {
      $self->{shutdown}->();
      delete $self->{timer};
      @rstate = ();
      my $error = "$@";
      $self->log ($error);
      return Promise->reject ($error);
    }
  }
  $self->{completed} = Promise->from_cv ($self->{global_cv})->then (sub {
    delete $self->{timer};
    @rstate = ();
    $self->log ("Main completed");
  });
  return $self->_create_workers_if_necessary (\@fh)->then (sub {
    return $self;
  });
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
  warn "Reference to @{[ref $_[0]]} ($_[0]->{id}) is not discarded before global destruction\
n"
      if $@ =~ /during global destruction/;
} # DESTROY

1;

=head1 LICENSE

Copyright 2016-2017 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
