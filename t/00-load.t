#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

use lib 'lib';
use_ok('SSH::Add');
use_ok('SSH::Bridge');

done_testing;
