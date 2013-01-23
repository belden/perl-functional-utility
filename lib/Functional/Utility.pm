use strict;
use warnings;
package Functional::Utility;
use base qw(Exporter);

use Time::HiRes ();

our @EXPORT_OK = qw(context hook_run_hook hook_run throttle);

# most of my modules start at 0.01. This one starts at 1.01 because
# I actually use this code in production.
our $VERSION = 1.01;

sub context {
	my ($lookback) = @_;
	my $wa = (caller($lookback || 0))[5];
	return 'VOID' unless defined $wa;
	return 'SCALAR' if !$wa;
	return 'LIST' if $wa;
}

sub hook_run_hook {
	my ($pre, $code, $post) = @_;

	$pre->() if $pre;

	my $callers_context = context(1);
	my @ret;
	+{
	  LIST => sub { @ret = $code->() },
	  SCALAR => sub { $ret[0] = $code->() },
	  VOID => sub { $code->(); return },
	}->{$callers_context}->();

	$post->() if $post;

	return $callers_context eq 'LIST' ? @ret : $ret[0];
}

sub hook_run {
	my (%args) = @_;
	return hook_run_hook(@args{qw(before run after)});
}

{
	my ($delay_time, $nth_run);
	sub throttle_delay (&$) {
		my ($code, $delay) = @_;
		my $delta = Time::HiRes::time - ($delay_time = Time::HiRes::time);
		Time::HiRes::sleep($delay - $delta) if $nth_run && $delay - $delta > 0;
		$nth_run ||= 1;
		$code->();
	}

	my ($ultimate_factor_duration, $penultimate_factor_duration);
	sub throttle_factor (&$) {
		my ($code, $factor) = @_;
		my $start;
		return hook_run_hook(
			sub {
				# If we're about to excute the 3rd or higher run, we can easily calculate how much we need to sleep
				# so the delay between runs is the right $factor.
				my $catchup = (($penultimate_factor_duration || 0) * $factor) - ($ultimate_factor_duration || 0);
				Time::HiRes::sleep($catchup) if $catchup > 0;

				# Are we about to execute the 2nd run? If so, we should sleep a little before executing so the delay
				# between the 1st and 2nd run is the right $factor.
				my $whoa_there_nelly = defined $ultimate_factor_duration && ! defined $penultimate_factor_duration;

				$penultimate_factor_duration = $ultimate_factor_duration;

				if ($whoa_there_nelly) {
					my $catchup = (($penultimate_factor_duration || 0) * $factor) - ($ultimate_factor_duration || 0);
					Time::HiRes::sleep($catchup) if $catchup > 0;
				}

				$start = Time::HiRes::time;
			},
			$code,
			sub {
				$ultimate_factor_duration = Time::HiRes::time - $start;
			},
		);
	}

	sub throttle (&@) {
		my $type = splice @_, 1, 1;
		goto &throttle_delay if $type eq 'delay';
		goto &throttle_factor;
	}
}

1;

__END__

=head1 NAME

Functional::Utility - utility functions for functions

=head1 SYNOPSIS

Throttle a given piece of code so it only runs once every N seconds:

    throttle { print scalar(localtime) . "\n" } delay => $N for 1..5;

Throttle a given piece of code so it waits N times as long between runs
as a single run takes:

    throttle { print scalar(localtime) . "\n"; sleep 1 } factor => $N for 1..5;

Add before and after hooks around some coderef, calling and returning coderef's output
back to caller in the correct context:

    my $start;

    hook_run(
      before => sub { $start = Time::HiRes::time },
      run    => $code,
      after  => sub { warn "running \$code took " . Time::HiRes::time - $start . " seconds\n" },
    );

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

(c) 2012 Belden Lyman <belden@cpan.org>

=head1 LICENSE

You may use and redistribute this software under the same terms as Perl itself.
