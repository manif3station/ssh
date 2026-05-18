package SSH::Bridge;

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempfile);

use SSH::Add;

sub new {
    my ( $class, %args ) = @_;
    return bless \%args, $class;
}

sub main {
    my ( $class, @argv ) = @_;
    my $self = ref($class) ? $class : $class->new;
    my $exit = eval { $self->execute(@argv) };
    if ( my $error = $@ ) {
        chomp $error;
        print STDERR "$error\n";
        return 2;
    }
    return $exit || 0;
}

sub execute {
    my ( $self, @argv ) = @_;
    my ( $server, $remote_port, $reconnect ) = $self->parse_args(@argv);
    my $add = $self->ssh_add;
    $add->ensure_skill_layout;
    my $socket = $add->ensure_agent;
    $add->set_auth_sock($socket);

    $self->ensure_identity_loaded( $server, $add );
    $self->clear_screen;
    return $self->run_loop( $server, $remote_port, $reconnect, $add );
}

sub parse_args {
    my ( $self, @argv ) = @_;
    die "Usage: dashboard ssh.bridge <ssh server> [remote-forward-port] [reconnect-seconds]\n" if !@argv;
    die "Usage: dashboard ssh.bridge <ssh server> [remote-forward-port] [reconnect-seconds]\n" if @argv > 3;

    my $server = shift @argv;
    die "Missing ssh server argument\n" if !defined $server || $server eq q{};

    my ( $remote_port, $reconnect );
    if (@argv == 2) {
        ( $remote_port, $reconnect ) = @argv;
    }
    elsif (@argv == 1) {
        if ( $self->is_bridge_host($server) ) {
            $remote_port = $argv[0];
        }
        else {
            $reconnect = $argv[0];
        }
    }

    if ( defined $remote_port ) {
        die "Remote forward port must be an integer from 1 to 65535\n"
          if $remote_port !~ /\A\d+\z/ || $remote_port < 1 || $remote_port > 65535;
        die "Remote forward port is supported only for hosts ending in .b\n"
          if !$self->is_bridge_host($server);
    }
    if ( defined $reconnect ) {
        die "Reconnect seconds must be a non-negative integer\n" if $reconnect !~ /\A\d+\z/;
    }

    return ( $server, $remote_port, $reconnect );
}

sub ssh_add {
    my ($self) = @_;
    return $self->{ssh_add} if $self->{ssh_add};
    my %args;
    $args{home} = $self->{home} if $self->{home};
    $args{skill_root} = $self->{skill_root} if $self->{skill_root};
    $args{env} = $self->{env} if $self->{env};
    $args{no_global_env} = $self->{no_global_env} if exists $self->{no_global_env};
    return $self->{ssh_add} = SSH::Add->new(%args);
}

sub ensure_identity_loaded {
    my ( $self, $server, $add ) = @_;
    return 1 if $self->identity_is_loaded($add);

    my $passphrase = $self->passphrase_for($server);
    die "No SSH key passphrase available for $server\n"
      if !defined $passphrase || $passphrase eq q{};

    my $askpass = $self->write_passphrase_askpass($passphrase);
    my $base_env = $self->{env} || \%ENV;
    my %env = (
        %{$base_env},
        SSH_AUTH_SOCK       => $add->active_agent_socket,
        SSH_ASKPASS         => $askpass,
        SSH_ASKPASS_REQUIRE => 'force',
    );
    delete $env{DISPLAY}
      if $self->{env}
      && exists $self->{env}{WAYLAND_DISPLAY}
      && !exists $self->{env}{DISPLAY};
    $env{DISPLAY} = $base_env->{DISPLAY} || $ENV{DISPLAY} || ':0'
      if !$base_env->{WAYLAND_DISPLAY} && !$env{DISPLAY};
    my $exit = $self->system_with_env( \%env, 'setsid', '-w', 'ssh-add', $self->identity_file );
    die "Failed to add " . $self->identity_file . " to ssh-agent\n" if $exit != 0;
    return 1;
}

sub identity_is_loaded {
    my ( $self, $add ) = @_;
    my $fingerprint = $add->key_fingerprint( $self->identity_file );
    return 0 if !defined $fingerprint;
    my %loaded = map { $_ => 1 } $add->loaded_key_fingerprints;
    return $loaded{$fingerprint} ? 1 : 0;
}

sub passphrase_for {
    my ( $self, $server ) = @_;
    my $env = $self->{env} || \%ENV;

    return $env->{BRIDGE_SSH_KEY_PASSPHRASE}
      if defined $env->{BRIDGE_SSH_KEY_PASSPHRASE} && length $env->{BRIDGE_SSH_KEY_PASSPHRASE};
    return $env->{SSH_KEY_PASSPHRASE}
      if defined $env->{SSH_KEY_PASSPHRASE} && length $env->{SSH_KEY_PASSPHRASE};

    return $env->{MACB_PASSPHRASE}
      if $server =~ /\Amac(?:\..*)?\z/i && defined $env->{MACB_PASSPHRASE} && length $env->{MACB_PASSPHRASE};
    return $env->{GPDB_PASSPHRASE}
      if $server =~ /\Agpd(?:\..*)?\z/i && defined $env->{GPDB_PASSPHRASE} && length $env->{GPDB_PASSPHRASE};
    return $env->{PASS}
      if $server =~ /\A(?:jump|(?:mac|gpd)\.b)\z/i && defined $env->{PASS} && length $env->{PASS};

    return undef;
}

sub write_passphrase_askpass {
    my ( $self, $passphrase ) = @_;
    return $self->{askpass_path} if $self->{askpass_path};

    my ( $fh, $path ) = tempfile( 'bridge-askpass-XXXXXX', TMPDIR => 1, UNLINK => 0 );
    print {$fh} "#!/bin/sh\n";
    print {$fh} "printf '%s\\n' ";
    print {$fh} _shell_quote($passphrase);
    print {$fh} "\n";
    close $fh;
    chmod 0700, $path or die "Unable to chmod $path: $!";
    $self->{askpass_path} = $path;
    return $path;
}

sub run_loop {
    my ( $self, $server, $remote_port, $reconnect, $add ) = @_;
    my $attempt = 0;
    while (1) {
        $self->connect_once( $server, $remote_port, $add );
        last if !defined $reconnect;
        $attempt++;
        last if $self->{max_attempts} && $attempt >= $self->{max_attempts};
        $self->sleep_for($reconnect);
    }
    return 0;
}

sub connect_once {
    my ( $self, $server, $remote_port, $add ) = @_;
    my $fh = $self->{stdout_fh} || \*STDOUT;
    print {$fh} "Connecting to $server ......\n";
    my @cmd = $self->ssh_command_for( $server, $remote_port );
    my %env = (
        %{ $self->{env} || \%ENV },
        SSH_AUTH_SOCK => $add->active_agent_socket,
    );
    return $self->system_with_env( \%env, @cmd );
}

sub ssh_command_for {
    my ( $self, $server, $remote_port ) = @_;
    my @cmd = ('ssh');
    if ( $self->is_bridge_host($server) ) {
        push @cmd,
          ( defined $remote_port ? ( '-o', "RemoteForward $remote_port localhost:22" ) : () ),
          '-o', 'ExitOnForwardFailure=yes',
          '-o', 'ServerAliveInterval=60',
          '-o', 'SessionType=none',
          '-o', 'RequestTTY=no';
    }
    push @cmd, '-v', $server;
    return @cmd;
}

sub is_bridge_host {
    my ( $self, $server ) = @_;
    my ($host) = $server =~ /\A(?:[^@]+@)?(.+)\z/;
    return defined $host && $host =~ /\.b\z/i ? 1 : 0;
}

sub clear_screen {
    my ($self) = @_;
    return $self->{clear_runner}->() if $self->{clear_runner};
    system 'clear';
    return 1;
}

sub sleep_for {
    my ( $self, $seconds ) = @_;
    return $self->{sleep_runner}->($seconds) if $self->{sleep_runner};
    sleep $seconds;
    return 1;
}

sub system_with_env {
    my ( $self, $env, @cmd ) = @_;
    return $self->{system_runner}->( $env, @cmd ) if $self->{system_runner};
    local %ENV = %{$env};
    system @cmd;
    return $? >> 8;
}

sub identity_file {
    my ($self) = @_;
    return $self->{identity_file} if $self->{identity_file};
    my $home = $self->{home} || $ENV{HOME} || die "HOME is required\n";
    return File::Spec->catfile( $home, '.ssh', 'id_ed25519' );
}

sub _shell_quote {
    my ($text) = @_;
    $text =~ s/'/'"'"'/g;
    return "'$text'";
}

1;
