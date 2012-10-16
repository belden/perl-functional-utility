package Functional::Utility;
use base qw(Exporter);

use strict;
use warnings;

our @EXPORT_OK = qw(context hook_run_hook throttle);
our $VERSION = 0.01;

sub context {
	my ($lookback) = @_;
	my $wa = (caller($lookback))[5];
	return 'VOID' unless defined $wa;
	return 'SCALAR' if !$wa;
	return 'LIST' if $wa;
}

sub hook_run_hook {
	my ($pre, $code, $post) = @_;

	$pre->();

	my $callers_context = context(1);
	my @ret;
	+{
	  LIST => sub { @ret = $code->() },
	  SCALAR => sub { $ret[0] = $code->() },
	  VOID => sub { $code->(); return },
	}->{$callers_context}->();

	$post->();

	return $callers_context eq 'LIST' ? @ret : $ret[0];
}

{
	my ($delay_time);
	use Time::HiRes ();
	sub throttle_delay (&$) {
		my ($code, $delay) = @_;
		my $delta = Time::HiRes::time - ($delay_time = Time::HiRes::time);
		Time::HiRes::sleep($delay - $delta) if $delay - $delta > 0;
		$code->();
	}

	sub hook_run_hook {
		my ($before, $code, $after) = @_;
		$before->();

		my @ret;
		if (wantarray) {
			@ret = $code->();
		} elsif (defined wantarray) {
			$ret[0] = $code->();
		} else {
			$code->();
		}

		$after->();
		return wantarray ? @ret : $ret[0];
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

Throttle a given piece of code so it waits three times as long between runs
as a single run takes:

    throttle { print scalar(localtime) . "\n"; sleep 1 } factor => 3 for 1..5;

=head1 BUGS

This documentation is frivolous.

=head1 AUTHOR

Belden Lyman <belden@cpan.org>
