{
	package Local::Test::Syntax;
	BEGIN {
		sub IMPORT {
			no strict 'refs';
			my $caller = caller;
			*{"$caller\::uc"} = sub ($) { lc $_[0] };
			*{"$caller\::maybe"} = sub {
				return @_ if defined $_[0] && defined $_[1];
				shift; shift; return @_;
			};
		}
	}
	use Syntax::Collector -collect => q/
		use strict 0;
		use warnings 0;
		use Scalar::Util 0 qw(blessed);
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
		plan tests => 5;
		
		is
			uc('Hello World'),
			'hello world',
			'sub IMPORT';
		
		warning_like { print undef }
			qr{^Use of uninitialized value in print},
			'use warnings';
		
		lives_ok { maybe(1,2) }
			'sub maybe';

		lives_and { ok blessed( bless +{} ) }
			'sub blessed';

		is_deeply
			[ sort Local::Test::Syntax->modules ],
			[ sort qw/strict warnings Scalar::Util/ ],
			'sub modules';
	}
}

Local::Test->go;
