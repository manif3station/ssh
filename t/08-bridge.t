#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use SSH::Bridge;

{
    package SSH::Bridge::TestAdd;

    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }

    sub ensure_skill_layout { return 1 }

    sub ensure_agent {
        my ($self) = @_;
        $self->{ensure_agent_calls}++;
        $self->{socket} ||= '/tmp/test-agent.sock';
        return $self->{socket};
    }

    sub set_auth_sock {
        my ( $self, $socket ) = @_;
        $self->{socket} = $socket;
        return $socket;
    }

    sub active_agent_socket {
        my ($self) = @_;
        return $self->{socket} || '/tmp/test-agent.sock';
    }

    sub key_fingerprint {
        my ( $self, $key ) = @_;
        $self->{key_fingerprint_calls}++;
        $self->{last_key_fingerprint_arg} = $key;
        return $self->{fingerprint};
    }

    sub loaded_key_fingerprints {
        my ($self) = @_;
        $self->{loaded_calls}++;
        return @{ $self->{loaded} || [] };
    }
}

{
    my $bridge = SSH::Bridge->new;
    is_deeply(
        [ $bridge->ssh_command_for( 'mac', 1223 ) ],
        [
            'ssh',
            '-o', 'RemoteForward 1223 localhost:22',
            '-o', 'ExitOnForwardFailure=yes',
            '-o', 'ServerAliveInterval=60',
            '-o', 'SessionType=none',
            '-o', 'RequestTTY=no',
            '-v', 'mac'
        ],
        'ssh.bridge always adds the bridge ssh options and remote forward'
    );
    is_deeply(
        [ $bridge->ssh_command_for('ops.example') ],
        [
            'ssh',
            '-o', 'ExitOnForwardFailure=yes',
            '-o', 'ServerAliveInterval=60',
            '-o', 'SessionType=none',
            '-o', 'RequestTTY=no',
            '-v', 'ops.example'
        ],
        'ssh.bridge always adds the bridge ssh options even without a remote port'
    );
}

{
    my $bridge = SSH::Bridge->new;
    is_deeply( [ $bridge->parse_args('mac') ], [ 'mac', undef, undef ], 'parse_args accepts server only' );
    is_deeply( [ $bridge->parse_args( 'mac', '1223' ) ], [ 'mac', '1223', undef ], 'parse_args treats the second arg as the remote forward port' );
    is_deeply( [ $bridge->parse_args( 'ops.example', '1223', '5' ) ], [ 'ops.example', '1223', '5' ], 'parse_args accepts remote port plus reconnect seconds for any host name' );
    like( eval { $bridge->parse_args(); 1 } ? q{} : $@, qr/Usage:/, 'missing args are rejected with usage' );
    like( eval { $bridge->parse_args( 'mac', '70000' ); 1 } ? q{} : $@, qr/1 to 65535/, 'remote forward port range is validated' );
    like( eval { $bridge->parse_args( 'mac', 'soon' ); 1 } ? q{} : $@, qr/1 to 65535/, 'bad remote forward port is rejected' );
    like( eval { $bridge->parse_args( 'mac', '1223', 'soon' ); 1 } ? q{} : $@, qr/non-negative integer/, 'bad reconnect value is rejected after a remote port' );
    like( eval { $bridge->parse_args( 'mac', '1', '2', 'extra' ); 1 } ? q{} : $@, qr/Usage:/, 'too many args are rejected' );
}

{
    my $bridge = SSH::Bridge->new(
        home          => tempdir( CLEANUP => 1 ),
        skill_root    => '/tmp/ssh-skill-root',
        env           => { DISPLAY => ':99' },
        no_global_env => 1,
    );
    my $add = $bridge->ssh_add;
    isa_ok( $add, 'SSH::Add', 'ssh_add creates an SSH::Add runner when one is not injected' );
    is( $bridge->ssh_add, $add, 'ssh_add caches the created runner' );
    is( $add->home, $bridge->{home}, 'created SSH::Add runner inherits the bridge home' );
}

{
    my $bridge = SSH::Bridge->new(
        env => {
            BRIDGE_SSH_KEY_PASSPHRASE => 'bridge-secret',
            SSH_KEY_PASSPHRASE        => 'ssh-secret',
            MACB_PASSPHRASE           => 'mac-secret',
            GPDB_PASSPHRASE           => 'gpd-secret',
            PASS                      => 'fallback-secret',
        },
    );
    is( $bridge->passphrase_for('mac.b'), 'bridge-secret', 'bridge-specific passphrase wins first' );

    $bridge = SSH::Bridge->new(
        env => {
            SSH_KEY_PASSPHRASE => 'ssh-secret',
            MACB_PASSPHRASE    => 'mac-secret',
            GPDB_PASSPHRASE    => 'gpd-secret',
            PASS               => 'fallback-secret',
        },
    );
    is( $bridge->passphrase_for('other'), 'ssh-secret', 'generic SSH passphrase is next fallback' );

    $bridge = SSH::Bridge->new(
        env => {
            MACB_PASSPHRASE => 'mac-secret',
            GPDB_PASSPHRASE => 'gpd-secret',
            PASS            => 'fallback-secret',
        },
    );
    is( $bridge->passphrase_for('mac.b'), 'mac-secret', 'mac host fallback is supported' );
    is( $bridge->passphrase_for('gpd.b'), 'gpd-secret', 'gpd host fallback is supported' );
    is( $bridge->passphrase_for('jump'), 'fallback-secret', 'legacy PASS fallback is supported for jump' );
    is( SSH::Bridge->new( env => {} )->passphrase_for('none'), undef, 'missing passphrase env returns undef' );
}

{
    my $bridge = SSH::Bridge->new(
        home          => tempdir( CLEANUP => 1 ),
        identity_file => '/tmp/custom-id',
    );
    is( $bridge->identity_file, '/tmp/custom-id', 'identity_file honors an explicit override' );
    my $quoted = SSH::Bridge::_shell_quote("pa'ss");
    is( $quoted, q{'pa'"'"'ss'}, 'shell quoting escapes single quotes safely' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $add = SSH::Bridge::TestAdd->new(
        fingerprint => 'SHA256:test',
        loaded      => ['SHA256:test'],
        socket      => '/tmp/active.sock',
    );
    my @system_calls;
    my $stdout = q{};
    open my $stdout_fh, '>', \$stdout or die $!;
    my $cleared = 0;
    my $bridge = SSH::Bridge->new(
        home          => $home,
        ssh_add       => $add,
        stdout_fh     => $stdout_fh,
        clear_runner  => sub { $cleared++; return 1 },
        system_runner => sub {
            my ( $env, @cmd ) = @_;
            push @system_calls, [ $env, @cmd ];
            return 0;
        },
    );

    is( $bridge->execute( 'user@mac', '1223' ), 0, 'execute succeeds for a named server' );
    is( $cleared, 1, 'bridge clears the screen before connecting' );
    like( $stdout, qr/Connecting to user\@mac/, 'bridge reports the target server' );
    is( scalar @system_calls, 1, 'loaded identity skips ssh-add passphrase injection' );
    is_deeply(
        [ @{ $system_calls[0] }[ 1 .. $#{ $system_calls[0] } ] ],
        [
            'ssh',
            '-o', 'RemoteForward 1223 localhost:22',
            '-o', 'ExitOnForwardFailure=yes',
            '-o', 'ServerAliveInterval=60',
            '-o', 'SessionType=none',
            '-o', 'RequestTTY=no',
            '-v', 'user@mac'
        ],
        'ssh.bridge command includes the requested options for a named server'
    );
    is( $system_calls[0][0]{SSH_AUTH_SOCK}, '/tmp/active.sock', 'ssh connect call uses the active agent socket' );
    like( $add->{last_key_fingerprint_arg}, qr/id_ed25519\z/, 'bridge checks the default bridge identity file' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $add = SSH::Bridge::TestAdd->new(
        fingerprint => 'SHA256:test',
        loaded      => [],
        socket      => '/tmp/active.sock',
    );
    my @system_calls;
    my $bridge = SSH::Bridge->new(
        home          => $home,
        ssh_add       => $add,
        env           => { MACB_PASSPHRASE => 'topsecret' },
        clear_runner  => sub { return 1 },
        system_runner => sub {
            my ( $env, @cmd ) = @_;
            push @system_calls, [ $env, @cmd ];
            return 0;
        },
    );

    is( $bridge->execute( 'mac', '1223' ), 0, 'bridge can load the identity before connecting' );
    is( $system_calls[0][1], 'setsid', 'bridge uses setsid for askpass-based ssh-add' );
    is( $system_calls[0][3], 'ssh-add', 'bridge invokes ssh-add when the key is not loaded' );
    is( $system_calls[0][0]{SSH_ASKPASS_REQUIRE}, 'force', 'askpass mode is forced for passphrase injection' );
    ok( -x $system_calls[0][0]{SSH_ASKPASS}, 'bridge writes an executable askpass helper' );
    is( $system_calls[0][0]{DISPLAY}, ':0', 'bridge supplies a default DISPLAY for askpass mode' );
    is( $system_calls[1][1], 'ssh', 'bridge connects after loading the key' );
}

{
    local $ENV{DISPLAY} = ':9';
    my $home = tempdir( CLEANUP => 1 );
    my $add = SSH::Bridge::TestAdd->new(
        fingerprint => 'SHA256:test',
        loaded      => [],
        socket      => '/tmp/active.sock',
    );
    my @system_calls;
    my $bridge = SSH::Bridge->new(
        home          => $home,
        ssh_add       => $add,
        env           => { MACB_PASSPHRASE => 'topsecret', WAYLAND_DISPLAY => 'wayland-0' },
        clear_runner  => sub { return 1 },
        system_runner => sub {
            my ( $env, @cmd ) = @_;
            push @system_calls, [ $env, @cmd ];
            return 0;
        },
    );

    ok( $bridge->ensure_identity_loaded( 'mac', $add ), 'bridge accepts wayland-only passphrase injection' );
    ok( !exists $system_calls[0][0]{DISPLAY}, 'bridge does not force DISPLAY when explicit wayland env is provided' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $add = SSH::Bridge::TestAdd->new(
        fingerprint => 'SHA256:test',
        loaded      => [],
        socket      => '/tmp/active.sock',
    );
    my $bridge = SSH::Bridge->new(
        home         => $home,
        ssh_add      => $add,
        clear_runner => sub { return 1 },
    );
    like(
        eval { $bridge->execute('mac'); 1 } ? q{} : $@,
        qr/No SSH key passphrase available for mac/,
        'missing passphrase env fails clearly when bridge is non-interactive'
    );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $add = SSH::Bridge::TestAdd->new(
        fingerprint => 'SHA256:test',
        loaded      => [],
        socket      => '/tmp/active.sock',
    );
    my @system_calls;
    my $bridge = SSH::Bridge->new(
        home          => $home,
        ssh_add       => $add,
        interactive   => 1,
        clear_runner  => sub { return 1 },
        system_runner => sub {
            my ( $env, @cmd ) = @_;
            push @system_calls, [ $env, @cmd ];
            return 0;
        },
    );
    is( $bridge->execute('mac'), 0, 'interactive bridge can load the key without passphrase env vars' );
    is( $system_calls[0][1], 'ssh-add', 'interactive fallback uses direct ssh-add' );
    is( $system_calls[1][1], 'ssh', 'interactive fallback continues to ssh after loading the key' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $add = SSH::Bridge::TestAdd->new(
        fingerprint => 'SHA256:test',
        loaded      => [],
        socket      => '/tmp/active.sock',
    );
    my $bridge = SSH::Bridge->new(
        home          => $home,
        ssh_add       => $add,
        env           => { MACB_PASSPHRASE => 'topsecret', WAYLAND_DISPLAY => 'wayland-0' },
        clear_runner  => sub { return 1 },
        system_runner => sub { return 1 },
    );
    like(
        eval { $bridge->ensure_identity_loaded( 'mac', $add ); 1 } ? q{} : $@,
        qr/Failed to add .*id_ed25519 to ssh-agent/,
        'ssh-add failure is reported clearly'
    );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $add = SSH::Bridge::TestAdd->new(
        fingerprint => 'SHA256:test',
        loaded      => [],
        socket      => '/tmp/active.sock',
    );
    my $bridge = SSH::Bridge->new(
        home          => $home,
        ssh_add       => $add,
        interactive   => 1,
        system_runner => sub { return 1 },
    );
    like(
        eval { $bridge->ensure_identity_loaded( 'mac', $add ); 1 } ? q{} : $@,
        qr/Failed to add .*id_ed25519 to ssh-agent/,
        'interactive ssh-add failure is reported clearly'
    );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $add = SSH::Bridge::TestAdd->new(
        fingerprint => undef,
        loaded      => [],
        socket      => '/tmp/active.sock',
    );
    my $bridge = SSH::Bridge->new( home => $home, ssh_add => $add );
    ok( !$bridge->identity_is_loaded($add), 'identity_is_loaded returns false when no fingerprint can be read' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $add = SSH::Bridge::TestAdd->new(
        fingerprint => 'SHA256:test',
        loaded      => ['SHA256:test'],
        socket      => '/tmp/active.sock',
    );
    my @sleep_calls;
    my @system_calls;
    my $bridge = SSH::Bridge->new(
        home          => $home,
        ssh_add       => $add,
        max_attempts  => 2,
        clear_runner  => sub { return 1 },
        sleep_runner  => sub { push @sleep_calls, $_[0]; return 1 },
        system_runner => sub {
            my ( $env, @cmd ) = @_;
            push @system_calls, [ $env, @cmd ];
            return 0;
        },
    );
    is( $bridge->execute( 'mac', '1223', '7' ), 0, 'bridge reconnect mode succeeds' );
    is( scalar @system_calls, 2, 'bridge reconnect mode runs the ssh command twice when max_attempts is set for tests' );
    is_deeply( \@sleep_calls, ['7'], 'bridge sleeps between reconnect attempts' );
}

{
    my $bridge = SSH::Bridge->new(
        home          => tempdir( CLEANUP => 1 ),
        ssh_add       => SSH::Bridge::TestAdd->new(
            fingerprint => 'SHA256:test',
            loaded      => ['SHA256:test'],
            socket      => '/tmp/active.sock',
        ),
        clear_runner  => sub { return 1 },
        system_runner => sub { return 0 },
    );
    is( $bridge->main('ops.example'), 0, 'main returns zero on success' );
    is( $bridge->main, 2, 'main returns 2 for invalid usage' );
}

{
    my $bridge = SSH::Bridge->new( interactive => 1 );
    ok( $bridge->is_interactive, 'is_interactive honors explicit interactive override' );
    $bridge = SSH::Bridge->new( interactive => 0 );
    ok( !$bridge->is_interactive, 'is_interactive honors explicit non-interactive override' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $bin = tempdir( CLEANUP => 1 );
    my $clear = File::Spec->catfile( $bin, 'clear' );
    open my $fh, '>', $clear or die $!;
    print {$fh} "#!/bin/sh\nexit 0\n";
    close $fh;
    chmod 0755, $clear or die $!;
    local $ENV{PATH} = $bin;

    my $bridge = SSH::Bridge->new( home => $home );
    is( $bridge->sleep_for(0), 1, 'default sleep_for returns success' );
    is( $bridge->system_with_env( { PATH => $ENV{PATH} }, $^X, '-e', 'exit 4' ), 4, 'default system_with_env returns command exit status' );
    is( $bridge->clear_screen, 1, 'default clear_screen runs the clear command' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $home, '.ssh' ) );
    my $bridge = SSH::Bridge->new( home => $home );
    my $askpass = $bridge->write_passphrase_askpass("pa'ss");
    ok( -x $askpass, 'write_passphrase_askpass creates an executable helper' );
    is( $bridge->write_passphrase_askpass('other'), $askpass, 'write_passphrase_askpass reuses the first helper path' );
}

done_testing;
