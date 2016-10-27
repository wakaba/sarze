use strict;
use warnings;
use Sarze;
use Path::Tiny;

my $host = 0;
my $port = 8522;
my $port2 = 8523;
my $path = path (__FILE__)->parent->parent->child ('local/test.sock')->absolute;

Sarze->run (
  hostports => [
    [$host, $port],
    [$host, $port2],
    ['unix/', $path->stringify],
  ],
  #eval => $code,
  psgi_file_name => "sketch/s2-app.psgi",
  #connections_per_worker => 2,
  #seconds_per_worker => 60,
)->to_cv->recv;
