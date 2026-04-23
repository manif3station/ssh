#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use JSON::PP qw(decode_json);
use Test::More;

open my $fh, '<', 'config/config.json' or die $!;
local $/;
my $config = decode_json(<$fh>);
close $fh;

is( ref $config->{collectors}, 'ARRAY', 'collector list exists' );
is( $config->{collectors}[0]{name}, 'door-opener', 'door-opener collector is declared' );
is( $config->{collectors}[0]{command}, 'dashboard ssh.add --collector', 'collector runs ssh.add in collector mode' );
is( $config->{collectors}[0]{interval}, 10, 'collector interval is ten seconds' );
is( $config->{collectors}[0]{indicator}{icon}, '🚪', 'collector indicator uses door icon' );

done_testing;
