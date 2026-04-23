#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;

use lib 'lib';
use SSH::Add;

sub harness {
    my (%args) = @_;
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $home, '.ssh' ) );
    my @system_calls;
    my @capture_calls;
    my $system = $args{system} || sub {
        my ( $env, @cmd ) = @_;
        push @system_calls, [ $env, @cmd ];
        return 0;
    };
    my $capture = $args{capture} || sub {
        my ( $env, @cmd ) = @_;
        push @capture_calls, [ $env, @cmd ];
        return ( q{}, q{}, 1 ) if $cmd[0] eq 'ssh-add' && $cmd[1] eq '-l';
        return ( q{}, q{}, 0 );
    };
    my $capture_command = $args{capture_command} || sub {
        my (@cmd) = @_;
        push @capture_calls, [ {}, @cmd ];
        return ( "SSH_AUTH_SOCK=$home/.ssh/ssh-agent/agent.sock; export SSH_AUTH_SOCK;\n", q{}, 0 )
          if $cmd[0] eq 'ssh-agent';
        return ( "256 SHA256:testfp key (ED25519)\n", q{}, 0 ) if $cmd[0] eq 'ssh-keygen';
        return ( q{}, q{}, 0 );
    };
    my $runner = SSH::Add->new(
        home            => $home,
        skill_root      => $root,
        env             => { SHELL => '/bin/bash' },
        no_global_env   => 1,
        system          => $system,
        capture         => $capture,
        capture_command => $capture_command,
        interactive     => $args{interactive} // 0,
    );
    return ( $runner, $home, $root, \@system_calls, \@capture_calls );
}

{
    my ( $runner, $home, $root, $system_calls ) = harness();
    _touch( File::Spec->catfile( $home, '.ssh', 'id_ed25519' ) );
    my $result = $runner->execute('id_ed25519');
    is( $result->{mode}, 'add', 'explicit key runs add mode' );
    is_deeply( $result->{added}, ['~/.ssh/id_ed25519'], 'bare key normalizes to home-relative ssh path in result' );
    is( _slurp( $runner->keys_file ), "~/.ssh/id_ed25519\n", 'bare key is remembered as home-relative path' );
    is( $system_calls->[-1][1], 'ssh-add', 'ssh-add command is called' );
    is( $system_calls->[-1][2], File::Spec->catfile( $home, '.ssh', 'id_ed25519' ), 'ssh-add receives expanded filesystem path' );
    is( $result->{registry}, File::Spec->catfile( $root, 'config', 'ssh', 'keys.txt' ), 'result exposes installed skill registry path' );
    is( $result->{shell_source}, 'source ~/.ssh/ssh-agent/agent.env', 'result exposes source command for current shell' );
    is_deeply( $result->{already_loaded}, [], 'fresh add reports no already-loaded keys' );
}

{
    my ( $runner, $home ) = harness();
    _touch( File::Spec->catfile( $home, '.ssh', 'id_ed25519' ) );
    $runner->execute('id_ed25519');
    $runner->execute('~/.ssh/id_ed25519');
    is( _slurp( $runner->keys_file ), "~/.ssh/id_ed25519\n", 'duplicate key is not written twice' );
}

{
    my @system_calls;
    my ( $runner, $home ) = harness(
        system => sub {
            my ( $env, @cmd ) = @_;
            push @system_calls, [ $env, @cmd ];
            return 0;
        },
        capture => sub {
            my ( $env, @cmd ) = @_;
            return ( "256 SHA256:testfp key\n", q{}, 0 ) if $cmd[0] eq 'ssh-add' && $cmd[1] eq '-l';
            return ( q{}, q{}, 0 );
        },
    );
    _touch( File::Spec->catfile( $home, '.ssh', 'id_ed25519' ) );
    my $result = $runner->execute('id_ed25519');
    is_deeply( $result->{added}, [], 'already-loaded key is not added again' );
    is_deeply( $result->{already_loaded}, ['~/.ssh/id_ed25519'], 'already-loaded key is reported separately' );
    my $add_calls = scalar grep { $_->[1] eq 'ssh-add' && $_->[2] ne '-l' } @system_calls;
    is( $add_calls, 0, 'ssh-add is not called again for already-loaded key' );
}

{
    my ( $runner, $home ) = harness();
    my $rsa = File::Spec->catfile( $home, '.ssh', 'id_rsa' );
    open my $fh, '>', $rsa or die $!;
    close $fh;
    my $result = $runner->execute();
    is_deeply( $result->{added}, ['~/.ssh/id_rsa'], 'no argument prefers id_rsa when it exists' );
}

{
    my ( $runner, $home ) = harness();
    my $ed = File::Spec->catfile( $home, '.ssh', 'id_ed25519' );
    open my $fh, '>', $ed or die $!;
    close $fh;
    my $result = $runner->execute();
    is_deeply( $result->{added}, ['~/.ssh/id_ed25519'], 'no argument falls back to id_ed25519' );
}

{
    my ( $runner ) = harness();
    my $error = eval { $runner->execute(); 1 };
    ok( !$error, 'missing default key dies' );
    like( $@, qr/no default key exists/, 'missing default key error explains fallback list' );
}

{
    my ( $runner ) = harness();
    $runner->write_keys(qw(~/.ssh/id_rsa ~/.ssh/id_ed25519));
    my $error = eval { $runner->execute('id_rsa'); 1 };
    ok( !$error, 'explicit missing key dies before ssh-add' );
    like( $@, qr/SSH key not found: ~\/\.ssh\/id_rsa/, 'missing explicit key error names normalized key' );
    is( _slurp( $runner->keys_file ), "~/.ssh/id_ed25519\n", 'missing explicit key is removed from stale registry without removing other keys' );
}

{
    my ( $runner, $home ) = harness();
    my $work_key = File::Spec->catfile( $home, 'work_key' );
    _touch($work_key);
    $runner->execute($work_key);
    is( _slurp( $runner->keys_file ), "$work_key\n", 'absolute key path is stored as supplied' );
    ok( -f File::Spec->catfile( $home, '.ssh', 'developer-dashboard-ssh-agent.conf' ), 'managed ssh config include file is written' );
    like( _slurp( File::Spec->catfile( $home, '.ssh', 'config' ) ), qr/Include ~\/\.ssh\/developer-dashboard-ssh-agent\.conf/, 'user ssh config includes managed file' );
}

{
    my ( $runner, $home ) = harness();
    _touch( File::Spec->catfile( $home, '.ssh', 'id_rsa' ) );
    my $env = $runner->agent_env_file;
    $runner->execute('id_rsa');
    like( _slurp($env), qr/^export SSH_AUTH_SOCK='/, 'agent env file is shell-readable' );
    like( _slurp( $runner->managed_ssh_include_file ), qr/IdentityAgent \Q$home\E\/\.ssh\/ssh-agent\/agent\.sock/, 'ssh include points at stable managed socket outside DD root' );
    like( _slurp( File::Spec->catfile( $home, '.bashrc' ) ), qr/\.ssh\/ssh-agent\/agent\.env/, 'bash startup sources managed agent env' );
}

sub _slurp {
    my ($file) = @_;
    open my $fh, '<', $file or die "Unable to read $file: $!";
    local $/;
    return <$fh>;
}

sub _touch {
    my ($file) = @_;
    open my $fh, '>', $file or die "Unable to create $file: $!";
    close $fh;
}

done_testing;
