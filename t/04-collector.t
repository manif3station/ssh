#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use SSH::Add;

sub runner_for {
    my (%args) = @_;
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $home, '.ssh' ) );
    my @system_calls;
    my $stderr = q{};
    open my $stderr_fh, '>', \$stderr or die $!;
    my $runner = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => {},
        no_global_env => 1,
        interactive   => $args{interactive} // 0,
        stderr_fh     => $stderr_fh,
        system        => sub {
            my ( $env, @cmd ) = @_;
            push @system_calls, [ $env, @cmd ];
            return 0;
        },
        capture => sub {
            my ( $env, @cmd ) = @_;
            return ( $args{loaded} || q{}, q{}, 0 ) if $cmd[0] eq 'ssh-add' && $cmd[1] eq '-l';
            return ( q{}, q{}, 0 );
        },
        capture_command => sub {
            my (@cmd) = @_;
            return ( "256 SHA256:key1 ~/.ssh/id_ed25519.pub (ED25519)\n", q{}, 0 ) if $cmd[0] eq 'ssh-keygen' && $cmd[2] =~ /id_ed25519/;
            return ( "256 SHA256:key2 ~/.ssh/id_rsa.pub (RSA)\n", q{}, 0 ) if $cmd[0] eq 'ssh-keygen' && $cmd[2] =~ /id_rsa/;
            return ( "SSH_AUTH_SOCK=$home/.developer-dashboard/ssh-agent/agent.sock; export SSH_AUTH_SOCK;\n", q{}, 0 );
        },
    );
    return ( $runner, $home, \@system_calls, \$stderr );
}

{
    my ( $runner, $home ) = runner_for( loaded => "256 SHA256:key1 card\n" );
    for my $name (qw(id_ed25519 id_rsa)) {
        open my $fh, '>', File::Spec->catfile( $home, '.ssh', "$name.pub" ) or die $!;
        close $fh;
    }
    $runner->write_keys(qw(~/.ssh/id_ed25519 ~/.ssh/id_rsa));
    my $result = $runner->execute('--collector');
    is( $result->{status}, 'missing', 'non-interactive collector reports missing keys' );
    is_deeply( $result->{missing}, ['~/.ssh/id_rsa'], 'collector reports only unloaded configured key' );
}

{
    my ( $runner, $home, $system_calls, $stderr ) = runner_for(
        loaded      => "256 SHA256:key1 card\n",
        interactive => 1,
    );
    for my $name (qw(id_ed25519 id_rsa)) {
        open my $fh, '>', File::Spec->catfile( $home, '.ssh', "$name.pub" ) or die $!;
        close $fh;
    }
    $runner->write_keys(qw(~/.ssh/id_ed25519 ~/.ssh/id_rsa));
    my $result = $runner->execute('--collector');
    is( $result->{status}, 'prompted', 'interactive collector prompts for missing keys' );
    like( $$stderr, qr/remembered but not loaded/, 'collector explains why passphrase is requested' );
    is( $system_calls->[-1][1], 'ssh-add', 'interactive collector runs ssh-add for missing key' );
}

{
    my ( $runner, $home ) = runner_for( loaded => "256 SHA256:key1 card\n" );
    open my $fh, '>', File::Spec->catfile( $home, '.ssh', 'id_ed25519.pub' ) or die $!;
    close $fh;
    $runner->write_keys('~/.ssh/id_ed25519');
    my $result = $runner->execute('--collector');
    is( $result->{status}, 'ok', 'collector returns ok when all remembered keys are loaded' );
    is_deeply( $result->{missing}, [], 'ok collector has no missing keys' );
}

{
    my ( $runner ) = runner_for();
    my $result = $runner->execute('--collector');
    is( $result->{status}, 'ok', 'collector with no configured keys is ok' );
    is( $result->{loaded}, 0, 'collector with no configured keys has zero loaded count' );
}

done_testing;
