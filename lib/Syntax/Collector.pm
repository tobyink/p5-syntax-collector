package Syntax::Collector;

use 5.008;
use strict;
use Carp;
use Module::Runtime qw/require_module/;

BEGIN {
	$Syntax::Collector::AUTHORITY = 'cpan:TOBYINK';
	$Syntax::Collector::VERSION   = '0.004';
}

sub import
{
	my $class = shift;
	
	my %opts;
	my $opt = 'collect';
	while (my $arg = shift @_)
	{
		if ($arg =~ /^-(.+)$/)
		{
			$opt = $1;
		}
		else
		{
			$opts{$opt} = $arg;
		}
	}
	
	croak "Need to provide a list of use lines to collect"
		unless defined $opts{collect} and $opts{collect};
	
	$opts{collect} = [$opts{collect}] unless ref $opts{collect};
	
	my @collect =
		grep { ! m/^#/ }                # not a comment
		grep { m/[A-Z0-9]/i }           # at least one alphanum
		map  { s/(^\s+)|(\s+$)//; $_ }  # trim
		map  { split /(\r?\n|\r)/ }     # split lines
		@{ $opts{collect} };
	
	my @features;
	
	foreach my $use_line (@collect)
	{
		if ($use_line =~ m{^
			(use|no) \s+      # "use" or "no"
			(\S+) \s+         # module name
			([\d\._v]+)       # module version
			(?:               # everything else
				\s* (.+)
			)?                #    ... perhaps
			[;] \s*           # semicolon
			$}x)
		{
			my ($use, $module, $version, $everything) = ($1, $2, $3, $4);
			$everything = '' unless defined $everything;
			
			if ($module =~ /^Syntax::Feature::/)
			{
				push @features, [FEATURE => $module, $version, [eval "($everything)"]]
					unless $use eq 'no';
			}
			else
			{
				push @features, [MODULE => $module, $version, [eval "($everything)"], $use];
			}
		}
		else
		{
			croak "Line q{$use_line} doesn't conform to 'use MODULE VERSION [ARGS];'";
		}
	}
	
	my %sub;
	$sub{import} = sub
	{
		my ($self, %args) = @_;
		my $caller = caller;
		
		foreach my $f (@features)
		{
			my ($type, $module, $version, $everything, $use) = @$f;
			
			if ($type eq 'FEATURE')
			{
				require_module($module);
				$module->VERSION($version) if $version;
				$module->install(into => $caller, @$everything);
			}
			else
			{
				require_module($module);
				$module->VERSION($version) if $version;
				my $coderef = $use eq 'no'
					? eval "package $caller; my \$sub = sub { shift->unimport(\@_) };"
					: eval "package $caller; my \$sub = sub { shift->import(\@_) };";
				$coderef->($module, @$everything);
			}
		}
		
		if (my $afterlife = $self->can('IMPORT'))
		{
			goto $afterlife;
		}
	};
	
	$sub{modules} = sub
	{
		my %modules =
			map { $_->[1] => $_->[2] }
			@features;
		return (wantarray ? keys(%modules) : \%modules);
	};
	
	my $caller = caller;
	for my $name (sort keys %sub)
	{
		my $code = $sub{$name};
		eval qq[package $caller; sub $name { goto \$code }];
	}
}

__FILE__
__END__

=pod

=encoding utf-8

=for stopwords DWIMmery pragmata

=head1 NAME

Syntax::Collector - collect a bundle of modules into one

=head1 SYNOPSIS

In lib/Example/ProjectX/Syntax.pm

  package Example::ProjectX::Syntax;
  
  use 5.010;
  our $VERSION = 1;
  
  use Syntax::Collector -collect => q/
    use strict 0;
    use warnings 0;
    use feature 0 ':5.10';
    use Scalar::Util 1.21 qw(blessed);
  /;
  
  1;
  __END__

In projectx.pl:

  #!/usr/bin/perl
  
  use Example::ProjectX::Database;
  use Example::ProjectX::Syntax 1;
  # strict, warnings, feature ':5.10', etc are now enabled!
  
  say "Welcome to ProjectX";

=head1 DESCRIPTION

Perl is such a flexible language that the language itself can be extended
from within. (Though much of the more interesting stuff needs XS hooks like
L<Devel::Declare>.)

One problem with this is that it often requires a lot of declarations at the
top of your code, loading various syntax extensions. The L<syntax> module on
CPAN addresses this somewhat by allowing you to load a bunch of features in
one line, provided each syntax feature implements the necessary API:

  use syntax qw/io maybe perform/;

However this introduces problems of its own. If we look at the code above,
it is non-obvious that it requires L<Syntax::Feature::Io>,
L<Syntax::Feature::Maybe> and L<Syntax::Feature::Perform>, which makes
it difficult for automated tools such as L<Module::Install> to automatically
calculate your code's dependencies.

Syntax::Collector to the rescue!

  package Example::ProjectX::Syntax;
  use 5.010;
  use Syntax::Collector -collect => q/
  use strict 0;
  use warnings 0;
  use feature 0 ':5.10';
  use Scalar::Util 1.21 qw(blessed);
  /;

When you C<use Syntax::Collector>, you provide a list of modules to
"collect" into a single package (notice the C<< q/.../ >>). This list
of modules looks like a big string of Perl code that is going to be
passed to C<eval>, but don't let that fool you - it is not.

Each line must conform to the following pattern:

  (use|no) MODULENAME VERSION (OTHERSTUFF)? ;

(Actually hash comments, and blank lines are also allowed.) The semantics
of all that is pretty much what you'd expect, except that when MODULENAME
begins with "Syntax::Feature::" it's treated with some DWIMmery, and
C<install> is called instead of C<import>. Note that VERSION is required,
but if you don't care which version of a module you use, it's fine to
set VERSION to 0. (Yes, VERSION is even required for pragmata.)

Now, you ask... why stuff all that structured data into a string, and
parse it out again? Because to naive lexical analysis (e.g.
L<Module::Install>) it really looks like a bunch of "use" lines, and
not just a single quoted string. This helps tools calculate the
dependencies of your collection; and thus the dependencies of other
code that uses your collection.

Because Syntax::Collector provides an C<import> method for your collection
package, you cannot provide your own. However, the C<import> method
provided will automatically call an C<IMPORT> method if it exists.
C<IMPORT> is passed a copy of the same arguments that were passed to
C<import>. (And indeed, it is invoked using C<goto> so it should be
safe to check C<< caller(0) >>.)

As well as providing an C<import> method for your collection,
Syntax::Collector also provides a C<modules> method, which can be called
to find out which modules a collection includes. Called in list context,
it returns a list. Called in scalar context, it returns a reference to a
C<< { module => version } >> hash.

=head1 A SYNTAX COLLECTION AND A UTILS COLLECTION

Your project's syntax module is also a natural place to keep any frequently
used utility functions, constants, etc. Thanks to the C<IMPORT> method
described above you can easily export these to the caller's namespace.

=head2 Using with Sub::Exporter

Sub::Exporter has an awesome feature set, so it is better than Exporter.pm.

  package Example::ProjectX::Syntax;
  our $VERSION = 1;
  
  use Syntax::Collector -collect => q/
  use strict 0;
  use warnings 0;
  use feature 0 ':5.10';
  use Scalar::Util 1.21 qw(blessed);
  /;
  
  use Sub::Exporter ();
  my $IMPORT = Sub::Exporter::build_exporter({
    exports  => [qw(true false)],
    groups   => { booleans => [qw(true false)] },
  });
  
  sub IMPORT {
    goto $IMPORT;
  }
  
  sub true  () { !!1 }
  sub false () { !!0 }
  
  1;

=head2 Using with Exporter.pm

Exporter.pm comes bundled with Perl, so it is better than Sub::Exporter.

  package Example::ProjectX::Syntax;
  our $VERSION = 1;
  
  use Syntax::Collector -collect => q/
  use strict 0;
  use warnings 0;
  use feature 0 ':5.10';
  use Scalar::Util 1.21 qw(blessed);
  /;
  
  use Exporter ();
  our @EXPORT_OK   = qw( true false );
  our %EXPORT_TAGS = (
    booleans => [qw( true false )],
  );
  
  sub IMPORT {
    goto &Exporter::import;
  }
  
  sub true  () { !!1 }
  sub false () { !!0 }
  
  1;

=head1 CAVEATS

You should not rely on the "use" lines being processed in any
particular order.

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=Syntax-Collector>.

=head1 SEE ALSO

L<syntax>, L<Sub::Exporter>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

