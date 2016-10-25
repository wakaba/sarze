use AnyEvent;

return sub {
  my $env = $_[0];

  #use Data::Dumper;
  #warn Dumper $env;

  if ($env->{PATH_INFO} eq '/1') {
    return sub {
      my $c = $_[0];
      AE::postpone {
        $c->([200, [], ['<p>1!']]);
      };
    };
  } elsif ($env->{PATH_INFO} eq '/2') {
    return sub {
      my $c = $_[0];
      AE::postpone {
        my $w = $c->([200, []]);
#        $w->write ("<p>");
#        $w->write ("x" x 1024);
#        $w->write ("x" x 1024);
        AE::postpone {
          $w->write ("<p>1!");
        };
        my $timer; $timer = AE::timer 1, 0, sub {
          AE::postpone {
            $w->write ("<p>2!");
          };
          AE::postpone {
            $w->write ("<p>3!");
          };
          AE::postpone {
            $w->close;
          };
          undef $timer;
        };
      };
    };
  } elsif ($env->{PATH_INFO} eq '/3') {
    return sub {
      my $c = $_[0];
      $env->{'psgix.exit_guard'}->begin;
      AE::postpone {
        my $w = $c->([200, []]);
        AE::postpone {
          $w->write ("<p>1!");
          $w->write ("<p>2!!");
          $w->write ("<p>3!");
          $w->write ("<p>4!");
        };
        AE::postpone {
          $w->close;
        };
      };
      my $timer; $timer = AE::timer 5, 0, sub {
        warn "4!";
        $env->{'psgix.exit_guard'}->end;
        undef $timer;
      };
    };
  } elsif ($env->{PATH_INFO} eq '/broken') {
    return sub {
      my $x = $_[0];
      my $y = {x => $x};
      $y->{y} = $y;
    };
  }

  return [200, [], ['200!']];
};
