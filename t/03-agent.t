#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use SSH::Add;

my $home = tempdir( CLEANUP => 1 );
my $root = tempdir( CLEANUP => 1 );
make_path( File::Spec->catdir( $home, '.ssh' ) );

my @system_calls;
my @capture_commands;
my @capture_calls;
my $runner = SSH::Add->new(
    home          => $home,
    skill_root    => $root,
    env           => { SSH_AUTH_SOCK => '/dead/socket' },
    no_global_env => 1,
    system        => sub {
        my ( $env, @cmd ) = @_;
        push @system_calls, [ $env, @cmd ];
        return 0;
    },
    capture => sub {
        my ( $env, @cmd ) = @_;
        push @capture_calls, [ $env, @cmd ];
        return ( q{}, 'dead socket', 2 ) if $cmd[0] eq 'ssh-add' && $cmd[1] eq '-l' && $env->{SSH_AUTH_SOCK} eq '/dead/socket';
        return ( 'The agent has no identities.', q{}, 1 ) if $cmd[0] eq 'ssh-add' && $cmd[1] eq '-l' && $env->{SSH_AUTH_SOCK} =~ /agent\.sock\z/;
        return ( q{}, q{}, 0 );
    },
    capture_command => sub {
        my (@cmd) = @_;
        push @capture_commands, \@cmd;
        return ( "SSH_AUTH_SOCK=$home/.ssh/ssh-agent/agent.sock; export SSH_AUTH_SOCK;\n", q{}, 0 );
    },
);

my $socket = $runner->ensure_agent;
like( $socket, qr/\.ssh\/ssh-agent\/agent\.sock\z/, 'dead SSH_AUTH_SOCK starts managed agent at stable socket outside DD root' );
is( $capture_commands[0][0], 'ssh-agent', 'ssh-agent is started' );
is( $capture_commands[0][1], '-a', 'ssh-agent receives explicit socket flag' );
is( $runner->{env}{SSH_AUTH_SOCK}, $socket, 'runner env is updated with managed socket' );
is( scalar(@system_calls), 0, 'ssh-add -l health checks do not use noisy system calls' );

{
    my @commands;
    my $reuse = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => { SSH_AUTH_SOCK => '/live/socket' },
        no_global_env => 1,
        system        => sub {
            my ( $env, @cmd ) = @_;
            push @commands, [ $env, @cmd ];
            return 0;
        },
        capture       => sub {
            my ( $env, @cmd ) = @_;
            push @commands, [ $env, @cmd ];
            return ( q{}, q{}, 0 );
        },
    );
    is( $reuse->ensure_agent, '/live/socket', 'live existing SSH_AUTH_SOCK is reused' );
    is( $reuse->{env}{SSH_AUTH_SOCK}, '/live/socket', 'reused live socket updates runner env' );
    is( _slurp( $reuse->agent_env_file ), "export SSH_AUTH_SOCK='/live/socket'\n", 'live socket is written for later sessions' );
}

{
    my $fail = SSH::Add->new(
        home            => tempdir( CLEANUP => 1 ),
        skill_root      => tempdir( CLEANUP => 1 ),
        env             => {},
        no_global_env   => 1,
        system          => sub { return 2 },
        capture_command => sub { return ( q{}, 'no agent', 1 ) },
    );
    my $ok = eval { $fail->ensure_agent; 1 };
    ok( !$ok, 'ssh-agent failure dies' );
    like( $@, qr/ssh-agent failed: no agent/, 'ssh-agent failure includes stderr' );
}

sub _slurp {
    my ($file) = @_;
    open my $fh, '<', $file or die $!;
    local $/;
    return <$fh>;
}

done_testing;
