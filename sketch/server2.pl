use strict;
use warnings;
use Sarze;

my $host = 0;
my $port = 8522;

Sarze->run (
  host => $host, port => $port,
  #eval => $code,
  psgi_file_name => "sketch/s2-app.psgi",
  #connections_per_worker => 2,
  #seconds_per_worker => 60,
)->to_cv->recv;
