BEGIN {
	package Syntax::Collector::Example;
	# hack for defining module inline
	$INC{'Syntax/Collector/Example.pm'} = __FILE__;
	use 5.010;
	use Syntax::Collector -collect => q/
		use feature 0 ':5.10';
		use strict 0;
		use warnings 0;
	/;
	sub IMPORT {
		my $caller = caller;
		*{"$caller\::maybe"} = sub {
			return @_ if defined $_[0] && defined $_[1];
			shift; shift; return @_;
		}
	}
};

package main;
use Syntax::Collector::Example;
say maybe(foo => 'l');
say undef;
