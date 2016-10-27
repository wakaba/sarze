use strict;
use warnings;
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('t_deps/lib')->stringify;
use Tests;

test {
  my $c = shift;

  my $server;
  promised_cleanup {
    return Promise->all ([
      (defined $server ? $server->stop : undef),
    ])->then (sub { done $c; undef $c });
  } Sarze->start (
    hostports => [],
    eval => q{
      sub main::psgi_app {
        return [200, [], [$_[0]->{HTTP_HOST}]];
      }
    },
  )->then (sub {
    $server = $_[0];
    test {
      ok 1;
    } $c;
  });
} n => 1;

run_tests;

=head1 LICENSE

Copyright 2016 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
