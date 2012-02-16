{
	package Local::Test::Syntax;
	BEGIN {
		sub IMPORT {
			no strict 'refs';
			my $caller = caller;
			*{"$caller\::uc"} = sub ($) { lc $_[0] };
		}
	}
	use Syntax::Collector -collect => q/
	use strict 0;
	use warnings 0;
	use Syntax::Feature::Maybe 0;
	/;
}

{
	package Local::Test;
	
	use strict;
	no warnings;
	use Test::More;
	use Test::Exception;
	use Test::Warn;
	BEGIN { Local::Test::Syntax->import };
	
	sub go
	{
		plan tests => 4;
		
		is
			uc('Hello World'),
			'hello world',
			'sub IMPORT';
		
		warning_like { print undef }
			qr{^Use of uninitialized value in print},
			'use warnings';
		
		lives_ok { maybe(1,2) }
			'use Syntax::Feature::Maybe';
		
		is_deeply
			[ sort Local::Test::Syntax->modules ],
			[ sort qw/strict warnings Syntax::Feature::Maybe/ ],
			'sub modules';
	}
}

Local::Test->go;
