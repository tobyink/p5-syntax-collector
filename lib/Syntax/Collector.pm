package Syntax::Collector;

use 5.008;
use strict;
use syntax qw//; # deliberate dependency.
use Carp;
use Module::Runtime qw/require_module/;
use Sub::Name qw/subname/;
use Sub::Uplevel qw/uplevel/;

BEGIN {
	$Syntax::Collector::AUTHORITY = 'cpan:TOBYINK';
	$Syntax::Collector::VERSION   = '0.001';
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
	
	$opts{collect}   = [$opts{collect}] unless ref $opts{collect};
	
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
			(?:
			  \s* (.+)        # everything else
			)?                #    ... perhaps
			[;] \s*           # semicolon
			$}x)
		{
			my ($use, $module, $version, $everything) = ($1, $2, $3, $4);
			
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
		my $self   = shift;
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
				my $func = $use eq 'no' ? 'unimport' : 'import';
				no strict 'refs';
				uplevel 1, \&{"$module\::$func"}, $module, @$everything;
			}
		}
		
		if (my $after = $self->can('IMPORT'))
		{
			@_ = ($self);
			goto $after;
		}
	};
	
	$sub{modules} = sub
	{
		my %modules =
			map { $_->[1] => $_->[2] }
			@features;
		return (wantarray ? keys(%modules) : \%modules);
	};
	
	{
		my $caller = caller;
		foreach my $sub (sort keys %sub)
		{
			my $subname = sprintf("%s::%s", $caller, $sub);
			no strict 'refs';
			*{$subname} = subname $caller => $sub{$sub};
		}
	}
}

__FILE__
__END__

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
  use Syntax::Feature::Io 0;
  use Syntax::Feature::Maybe 0;
  use Syntax::Feature::Perform 0;
  /;
  __FILE__
  __END__

In projectx.pl:

  use Example::ProjectX::Syntax 1;
  # strict, warnings, feature ':5.10', etc are now enabled!
  
  use Example::ProjectX::Database;
  
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
  use Syntax::Feature::Io 0;
  use Syntax::Feature::Maybe 0;
  use Syntax::Feature::Perform 0;
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
provided will automatically call a C<IMPORT> method if it exists. So you
can do this:

  package Example::ProjectX::Syntax;
  
  use 5.010;
  our $VERSION = 1;
  
  use constant {
    PROJECT_NAME => 'Project X',
    PROJECT_LEAD => 'Joe Bloggs',
  };
  
  BEGIN {
    sub IMPORT {
      no strict 'refs';
      my $caller = caller;
      *{"$caller\::PROJECT_NAME"} = \&PROJECT_NAME;
      *{"$caller\::PROJECT_LEAD"} = \&PROJECT_LEAD;
      *{"$caller\::add"} = \&add;
    }
  }
  
  use Syntax::Collector -collect => q/
  use strict 0;
  use warnings 0;
  use feature 0 ':5.10';
  use Syntax::Feature::Io 0;
  use Syntax::Feature::Maybe 0;
  use Syntax::Feature::Perform 0;
  /;
  
  sub add {
    my $x = shift;
    return $x + add(@_);
  }
  
  __FILE__
  __END__

As well as providing an C<import> method for your collection,
Syntax::Collector also provides a C<modules> method, which can be called
to find out which modules a collection includes. Called in list context,
it returns a list. Called in scalar context, it returns a reference to a
C<< { module => version } >> hash.

=head1 CAVEATS

This module does some pretty tricky stuff with L<Sub::Uplevel> and
C<eval>. It is possible that (especially in the case of convoluted
OVERSTUFF), certain "use" lines may break.

You should not rely on the "use" lines being processed in any
particular order.

=head2 Using with Exporter

It's a natural desire to want to use Syntax::Collector with Exporter. Because
both of these modules want to provide you with an C<import> method, you
need to resolve that manually:

  package Example::ProjectX::Syntax;
  
  use 5.010;
  our $VERSION = 1;
  
  use constant {
    PROJECT_NAME => 'Project X',
    PROJECT_LEAD => 'Joe Bloggs',
  };
  
  our (@EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  BEGIN {
    require qw/Exporter/;
    @EXPORT      = qw/ ... /;
    @EXPORT_OK   = qw/ ... /;
    %EXPORT_TAGS = (
        ':standard' => \@EXPORT,
        ':all'      => \@EXPORT_OK,
        ...);
    sub IMPORT {
      goto &Exporter::import;
    }
  }
  
  use Syntax::Collector -collect => q/
  use strict 0;
  use warnings 0;
  ...
  /;
  
  1;

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=Syntax-Collector>.

=head1 SEE ALSO

L<syntax>, L<Exporter>.

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

