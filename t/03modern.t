BEGIN {
	package Local::Test::Syntax;
	
	use Syntax::Collector q/
		use strict 0;
		use warnings 0;
		use Scalar::Util 0 qw(blessed);
	/;
	
	our @EXPORT = qw( uc maybe );
	
	sub uc ($) { lc $_[0] };
	sub maybe {
		return @_ if defined $_[0] && defined $_[1];
		shift; shift; return @_;
	}
}

{
	package Local::Test;
	
	use strict;
	no warnings;
	use Test::More;
	use Test::Exception;
	use Test::Warn;
	
	use Local::Test::Syntax;
	
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
