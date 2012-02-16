package Syntax::Collector::Example;

use 5.010;
use Syntax::Collector -collect => q/
use feature 0 ':5.10';
use strict 0;
use warnings 0;
use Syntax::Feature::Maybe 0;
/;

1;
