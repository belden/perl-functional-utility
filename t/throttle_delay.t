#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;

use lib grep { -d $_ } qw(./lib ../lib ./t/lib);
use Functional::Utility qw(throttle);  # this is in lib/
use Test::Resub qw(resub);             # this comes from t/lib/
use Test::Facile qw(nearly each_ok);   # this comes from t/lib/

# declare our intent to muck with the world
BEGIN { *CORE::GLOBAL::sleep = \&CORE::sleep }

use Time::HiRes ();

# muck with sleep
my $rs_hires_sleep = resub 'Time::HiRes::sleep', sub {};
my $rs_core_sleep = resub 'CORE::GLOBAL::sleep', sub {};

# throttle with a delay => $n: we'll wait $n seconds between runs
my $sleep = 1;
my @times;
throttle { sleep $sleep++ } delay => .5 for 1..3;
is_deeply( $rs_core_sleep->args, [[1], [2], [3]], 'throttled code would have slept 1, 2, then 3 seconds' );
each_ok { nearly($_->[0], .5, .1) } @{$rs_hires_sleep->args};
is( $rs_hires_sleep->called, 2, 'we slept twice' );
