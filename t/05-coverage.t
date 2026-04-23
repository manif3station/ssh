#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Socket::UNIX;
use Test::More;

use lib 'lib';
use SSH::Add;

{
    package SSH::Add::TestWait;
    use parent 'SSH::Add';

    sub ssh_add_list_rc {
        my ($self) = @_;
        $self->{checks}++;
        return $self->{checks} > 1 ? 1 : 2;
    }
}

{
    package SSH::Add::TestWaitFail;
    use parent 'SSH::Add';

    sub ssh_add_list_rc {
        my ($self) = @_;
        $self->{checks}++;
        return 2;
    }
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    my $runner = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => {},
        no_global_env => 1,
        system        => sub { return 0 },
        capture       => sub { return ( q{}, q{}, 0 ) },
        capture_command => sub { return ( q{}, q{}, 0 ) },
    );
    like( eval { $runner->execute('--bad'); 1 } ? q{} : $@, qr/Unsupported option/, 'unsupported option is rejected' );
    like( eval { $runner->normalize_key_path(undef); 1 } ? q{} : $@, qr/Missing key path/, 'missing key path is rejected' );
    ok( SSH::Add->main('--bad') == 2, 'main can be called as a class method' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $home, '.ssh' ) );
    my $runner = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => {},
        no_global_env => 1,
        system        => sub { return 1 },
        capture       => sub { return ( q{}, q{}, 0 ) },
        capture_command => sub { return ( q{}, q{}, 0 ) },
    );
    $runner->ensure_skill_layout;
    like( eval { $runner->run_ssh_add('~/.ssh/missing'); 1 } ? q{} : $@, qr/ssh-add failed/, 'ssh-add failure is reported' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    my @capture;
    my $runner = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => {},
        no_global_env => 1,
        system        => sub {
            my ( $env, @cmd ) = @_;
            return 2 if $cmd[0] eq 'ssh-add' && $cmd[1] eq '-l';
            return 0;
        },
        capture => sub {
            my ( $env, @cmd ) = @_;
            return ( q{}, q{}, 0 );
        },
        capture_command => sub {
            my (@cmd) = @_;
            push @capture, \@cmd;
            return ( "SSH_AUTH_SOCK=$home/.ssh/ssh-agent/agent.sock; export SSH_AUTH_SOCK;\n", q{}, 0 );
        },
    );
    make_path( $runner->agent_dir );
    open my $stale, '>', $runner->agent_socket or die $!;
    print {$stale} "stale\n";
    close $stale;
    $runner->ensure_agent;
    ok( @capture, 'stale socket path triggers fresh ssh-agent start' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    my $runner = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => {},
        no_global_env => 1,
        system        => sub { return 0 },
        capture       => sub { return ( q{}, q{}, 0 ) },
    );
    make_path( $runner->agent_dir );
    my $server = IO::Socket::UNIX->new(
        Type   => SOCK_STREAM,
        Local  => $runner->agent_socket,
        Listen => 1,
    );
    ok( $server, 'test unix socket created' );
    is( $runner->ensure_agent, $runner->agent_socket, 'existing live managed socket is reused' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    my $runner = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => {},
        no_global_env => 1,
        system        => sub { return 0 },
        capture => sub { return ( q{}, q{}, 5 ) },
    );
    is_deeply( [ $runner->loaded_key_fingerprints ], [], 'ssh-add -l failure returns no loaded fingerprints' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    my $runner = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => {},
        no_global_env => 1,
        system        => sub { return 0 },
        capture => sub { return ( "no fingerprint here\n256 SHA256:real key\n", q{}, 0 ) },
    );
    is_deeply( [ $runner->loaded_key_fingerprints ], ['SHA256:real'], 'loaded fingerprints skip unrelated ssh-add lines' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $home, '.ssh' ) );
    my $key = File::Spec->catfile( $home, '.ssh', 'raw_key' );
    open my $fh, '>', $key or die $!;
    close $fh;
    my $runner = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => {},
        no_global_env => 1,
        capture_command => sub {
            my (@cmd) = @_;
            return ( q{}, q{}, 4 ) if $cmd[2] =~ /bad/;
            return ( "not a fingerprint\n", q{}, 0 ) if $cmd[2] =~ /raw_key/;
            return ( q{}, q{}, 0 );
        },
    );
    is( $runner->key_fingerprint('~/.ssh/no-file'), undef, 'missing key file has no fingerprint' );
    is( $runner->key_fingerprint('~/.ssh/raw_key'), undef, 'keygen output without fingerprint returns undef' );
    open my $bad, '>', File::Spec->catfile( $home, '.ssh', 'bad.pub' ) or die $!;
    close $bad;
    is( $runner->key_fingerprint('~/.ssh/bad'), undef, 'keygen failure returns undef' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $runner = SSH::Add->new( home => $home, env => {}, no_global_env => 1, shell_profile_file => undef );
    is( $runner->ensure_shell_agent_bridge, 1, 'shell bridge is skipped when no shell profile is selected' );
    is( SSH::Add->new( home => $home, env => { SHELL => '/bin/zsh' } )->shell_profile_file, File::Spec->catfile( $home, '.zshrc' ), 'zsh uses zshrc bridge' );
    my $profile = File::Spec->catfile( $home, '.profile' );
    open my $fh, '>', $profile or die $!;
    print {$fh} "existing";
    close $fh;
    my $profile_runner = SSH::Add->new( home => $home, env => { SHELL => '/bin/fish' } );
    $profile_runner->ensure_shell_agent_bridge;
    like( _slurp($profile), qr/existing\n# Developer Dashboard/, 'profile bridge preserves content without trailing newline' );
    $profile_runner->ensure_shell_agent_bridge;
    is( () = _slurp($profile) =~ /^\[ -f "\$HOME\/\.ssh\/ssh-agent\/agent\.env" \]/mg, 1, 'profile bridge is not duplicated' );
}

{
    my $runner = SSH::Add->new;
    is( $runner->parse_agent_socket(undef), undef, 'agent socket parser handles missing stdout' );
    is( $runner->parse_agent_socket("SSH_AUTH_SOCK='/tmp/quoted.sock'; export SSH_AUTH_SOCK;\n"), '/tmp/quoted.sock', 'agent socket parser handles quoted output' );
}

{
    my $runner = SSH::Add->new(
        env => { DISPLAY => ':1' },
        capture_command => sub {
            my (@cmd) = @_;
            return ( q{}, q{}, 0 ) if $cmd[-1] =~ /zenity/;
            return ( q{}, q{}, 1 );
        },
    );
    ok( $runner->can_gui_prompt, 'gui prompt is available when display exists and a backend command is present' );
    ok( !$runner->command_available(undef), 'command_available returns false for undefined command names' );
    ok( !$runner->command_available('missing-backend'), 'command_available returns false for missing commands' );
}

{
    my $runner = SSH::Add->new(
        env => {},
        capture_command => sub { return ( q{}, q{}, 1 ) },
    );
    ok( !$runner->can_gui_prompt, 'gui prompt is unavailable without display or wayland session' );
}

{
    my $runner = SSH::Add->new(
        env => { WAYLAND_DISPLAY => 'wayland-0' },
        capture_command => sub {
            my (@cmd) = @_;
            return ( q{}, q{}, 0 ) if $cmd[-1] =~ /ssh-askpass/;
            return ( q{}, q{}, 1 );
        },
    );
    ok( $runner->can_gui_prompt, 'wayland session can use askpass backend discovery' );
}

{
    my $runner = SSH::Add->new(
        env => { DISPLAY => ':1' },
        capture_command => sub {
            my (@cmd) = @_;
            return ( q{}, q{}, 0 ) if $cmd[-1] =~ /x11-ssh-askpass/;
            return ( q{}, q{}, 1 );
        },
    );
    ok( $runner->can_gui_prompt, 'x11-ssh-askpass backend is accepted when available' );
}

{
    my $runner = SSH::Add->new(
        env => { DISPLAY => ':1' },
        capture_command => sub { return ( q{}, q{}, 1 ) },
    );
    ok( !$runner->can_gui_prompt, 'display alone is not enough without any askpass backend' );
}

{
    my $runner = SSH::Add->new(
        system_no_tty => sub {
            my ( $env, @cmd ) = @_;
            return $env->{SSH_ASKPASS} && $env->{SSH_ASKPASS_REQUIRE} eq 'force' ? 0 : 1;
        },
    );
    like( $runner->collector_prompt_message('~/.ssh/id_ed25519'), qr/needs the passphrase/, 'collector prompt message is explanatory' );
    ok( $runner->run_ssh_add_askpass('~/.ssh/id_ed25519'), 'run_ssh_add_askpass succeeds through askpass environment' );
    my $helper = $runner->write_askpass_helper;
    ok( -x $helper, 'askpass helper script is created as executable' );
    is( $runner->write_askpass_helper, $helper, 'askpass helper is reused after first creation' );
}

{
    my @calls;
    my $runner = SSH::Add->new(
        env => {},
        system_no_tty => sub {
            my ( $env, @cmd ) = @_;
            push @calls, [ $env, @cmd ];
            return 0;
        },
    );
    ok( $runner->run_ssh_add_askpass('~/.ssh/id_ed25519'), 'askpass path succeeds when display fallback is required' );
    is( $calls[0][0]{DISPLAY}, ':0', 'askpass path supplies DISPLAY fallback when no UI env is preset' );
}

{
    my @calls;
    my $runner = SSH::Add->new(
        env => { WAYLAND_DISPLAY => 'wayland-0' },
        system_no_tty => sub {
            my ( $env, @cmd ) = @_;
            push @calls, [ $env, @cmd ];
            return 0;
        },
    );
    ok( $runner->run_ssh_add_askpass('~/.ssh/id_ed25519'), 'askpass path succeeds with wayland display' );
    ok( !exists $calls[0][0]{DISPLAY}, 'askpass path does not force DISPLAY when wayland is already available' );
}

{
    my $runner = SSH::Add->new(
        system_no_tty => sub { return 1 },
    );
    like(
        eval { $runner->run_ssh_add_askpass('~/.ssh/id_ed25519'); 1 } ? q{} : $@,
        qr/ssh-add failed for ~\/\.ssh\/id_ed25519/,
        'askpass path reports ssh-add failure'
    );
}

{
    my $runner = SSH::Add::TestWait->new;
    is( $runner->wait_for_agent('/tmp/test-agent.sock'), 1, 'wait_for_agent retries until socket responds' );
    is( $runner->{checks}, 2, 'wait_for_agent performed retry checks' );
    my $fail = SSH::Add::TestWaitFail->new;
    my $ok = eval { $fail->wait_for_agent('/tmp/test-agent.sock'); 1 };
    ok( !$ok, 'wait_for_agent dies when socket never responds' );
    like( $@, qr/socket is not usable/, 'wait_for_agent failure explains unusable socket' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    my $runner = SSH::Add->new( home => $home, skill_root => $root );
    make_path( File::Spec->catdir( $home, '.ssh' ) );
    open my $cfg, '>', File::Spec->catfile( $home, '.ssh', 'config' ) or die $!;
    print {$cfg} "Host github\n  HostName github.com";
    close $cfg;
    $runner->ensure_ssh_config_bridge;
    like( _slurp( File::Spec->catfile( $home, '.ssh', 'config' ) ), qr/github\.com\n# Developer Dashboard/s, 'include append preserves config without trailing newline' );
    $runner->ensure_ssh_config_bridge;
    my $content = _slurp( File::Spec->catfile( $home, '.ssh', 'config' ) );
    is( () = $content =~ /Include ~\/\.ssh\/developer-dashboard-ssh-agent\.conf/g, 1, 'managed include is not duplicated' );
}

{
    my $runner = SSH::Add->new;
    is( $runner->result_exit_code( { mode => 'collector', status => 'missing' } ), 1, 'collector missing result maps to nonzero exit' );
    is( $runner->result_exit_code( { mode => 'collector', status => 'ok' } ), 0, 'collector ok result maps to zero exit' );
    is( $runner->result_exit_code( { mode => 'add', status => 'missing' } ), 0, 'non-collector results stay zero' );
}

{
    my $runner = SSH::Add->new;
    my $exit = $runner->system_with_env_no_tty( { PATH => $ENV{PATH} }, $^X, '-e', 'exit 4' );
    is( $exit, 4, 'default no-tty system runner returns command exit code' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_CONFIG_ROOT} = File::Spec->catdir( $root, 'custom-config' );
    local $ENV{DEVELOPER_DASHBOARD_SKILL_STATE_ROOT}  = File::Spec->catdir( $root, 'custom-state' );
    my $runner = SSH::Add->new( home => $home, skill_root => $root );
    is( $runner->config_root, $ENV{DEVELOPER_DASHBOARD_SKILL_CONFIG_ROOT}, 'config root honors DD env' );
    is( $runner->state_dir, $ENV{DEVELOPER_DASHBOARD_SKILL_STATE_ROOT}, 'state root honors DD env' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    local $ENV{HOME} = $home;
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} = tempdir( CLEANUP => 1 );
    my $runner = SSH::Add->new;
    is( $runner->skill_root, $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT}, 'skill root honors DD env' );
    is( $runner->home, $home, 'home falls back to HOME env' );
}

{
    my $cwd = getcwd();
    my $root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $root, 'cli' ), File::Spec->catdir( $root, 'lib' ) );
    chdir $root or die $!;
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT};
    my $runner = SSH::Add->new;
    is( $runner->skill_root, $root, 'skill root can be inferred from cwd' );
    chdir $cwd or die $!;
}

{
    my $cwd = getcwd();
    my $empty = tempdir( CLEANUP => 1 );
    chdir $empty or die $!;
    local $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT};
    my $runner = SSH::Add->new;
    like( $runner->skill_root, qr/skills\/ssh\z/, 'skill root falls back to module location' );
    chdir $cwd or die $!;
}

{
    my $runner = SSH::Add->new( no_global_env => 0, env => {} );
    local $ENV{SSH_AUTH_SOCK};
    $runner->set_auth_sock('/tmp/dd-agent.sock');
    is( $ENV{SSH_AUTH_SOCK}, '/tmp/dd-agent.sock', 'set_auth_sock updates global env by default' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $runner = SSH::Add->new( home => $home, env => {}, no_global_env => 1 );
    $runner->write_agent_env('/tmp/quoted-agent.sock');
    is( $runner->read_agent_env, '/tmp/quoted-agent.sock', 'read_agent_env reads quoted shell export' );
    open my $fh, '>', $runner->agent_env_file or die $!;
    print {$fh} "SSH_AUTH_SOCK=/tmp/plain-agent.sock; export SSH_AUTH_SOCK;\n";
    close $fh;
    is( $runner->read_agent_env, '/tmp/plain-agent.sock', 'read_agent_env reads plain ssh-agent output format' );
    open my $bad, '>', $runner->agent_env_file or die $!;
    print {$bad} "no socket here\n";
    close $bad;
    is( $runner->read_agent_env, undef, 'read_agent_env returns undef when no socket assignment exists' );
}

{
    my $runner = SSH::Add->new;
    ok( defined $runner->is_interactive, 'is_interactive falls back to terminal detection' );
}

{
    my $runner = SSH::Add->new;
    my $exit = $runner->system_with_env( { PATH => $ENV{PATH} }, $^X, '-e', 'exit 3' );
    is( $exit, 3, 'default system runner returns command exit code' );
    my ( $stdout, undef, $capture_exit ) = $runner->capture_with_env( { PATH => $ENV{PATH} }, 'printf', 'hello' );
    is( $stdout, 'hello', 'default capture runner captures stdout' );
    is( $capture_exit, 0, 'default capture runner reports exit code' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    my $runner = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => {},
        no_global_env => 1,
        system        => sub { return 0 },
        capture       => sub { return ( q{}, q{}, 0 ) },
        capture_command => sub { return ( q{}, q{}, 0 ) },
    );
    $runner->write_keys( '', '#comment', '~/.ssh/id_ed25519' );
    is_deeply( [ $runner->read_keys ], ['~/.ssh/id_ed25519'], 'read_keys skips blanks and comments' );
}

{
    my $home = tempdir( CLEANUP => 1 );
    my $root = tempdir( CLEANUP => 1 );
    my $runner = SSH::Add->new(
        home          => $home,
        skill_root    => $root,
        env           => {},
        no_global_env => 1,
        system        => sub { return 0 },
        capture       => sub { return ( q{}, q{}, 0 ) },
        capture_command => sub { return ( q{}, q{}, 0 ) },
    );
    make_path( File::Spec->catdir( $home, '.ssh' ) );
    open my $key, '>', File::Spec->catfile( $home, '.ssh', 'id_ed25519' ) or die $!;
    close $key;
    my $out_file = File::Spec->catfile( $home, 'stdout.txt' );
    open my $oldout, '>&', \*STDOUT or die $!;
    open STDOUT, '>', $out_file or die $!;
    my $code = $runner->main('id_ed25519');
    open STDOUT, '>&', $oldout or die $!;
    is( $code, 0, 'main returns zero on success' );
    like( _slurp($out_file), qr/"mode":"add"/, 'main prints JSON result' );
}

{
    my $runner = SSH::Add->new(
        home          => tempdir( CLEANUP => 1 ),
        skill_root    => tempdir( CLEANUP => 1 ),
        env           => {},
        no_global_env => 1,
        system        => sub { return 0 },
        capture       => sub { return ( q{}, q{}, 0 ) },
        capture_command => sub { return ( q{}, q{}, 0 ) },
    );
    my $err_file = File::Spec->catfile( $runner->home, 'stderr.txt' );
    open my $olderr, '>&', \*STDERR or die $!;
    open STDERR, '>', $err_file or die $!;
    my $code = $runner->main('--bad');
    open STDERR, '>&', $olderr or die $!;
    is( $code, 2, 'main returns nonzero on error' );
    like( _slurp($err_file), qr/Unsupported option/, 'main prints error message' );
}

sub _slurp {
    my ($file) = @_;
    open my $fh, '<', $file or die $!;
    local $/;
    return <$fh>;
}

done_testing;
