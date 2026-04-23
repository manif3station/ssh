package SSH::Add;

use strict;
use warnings;

use Cwd qw(getcwd abs_path);
use File::Basename qw(dirname basename);
use File::Path qw(make_path);
use File::Spec;
use JSON::PP qw(encode_json);

my $MODULE_FILE = abs_path(__FILE__) || __FILE__;

sub new {
    my ( $class, %args ) = @_;
    return bless \%args, $class;
}

sub main {
    my ( $class, @argv ) = @_;
    my $self = ref($class) ? $class : $class->new;
    my $result = eval { $self->execute(@argv) };
    if ( my $error = $@ ) {
        chomp $error;
        print STDERR "$error\n";
        return 2;
    }
    print encode_json($result), "\n";
    return 0;
}

sub execute {
    my ( $self, @argv ) = @_;
    my $collector = 0;
    my @keys;
    while (@argv) {
        my $arg = shift @argv;
        if ( $arg eq '--collector' ) {
            $collector = 1;
            next;
        }
        die "Unsupported option: $arg" if $arg =~ /^-/;
        push @keys, $arg;
    }

    $self->ensure_skill_layout;
    $self->ensure_agent;
    $self->ensure_ssh_config_bridge;

    return $self->collector_check if $collector;
    return $self->add_keys(@keys);
}

sub add_keys {
    my ( $self, @keys ) = @_;
    @keys = ( $self->default_key ) if !@keys;
    die "No SSH key argument supplied and no default key exists at ~/.ssh/id_rsa or ~/.ssh/id_ed25519"
      if !@keys || !defined $keys[0];

    my @normalized = map { $self->normalize_key_path($_) } @keys;
    $self->remember_keys(@normalized);

    my @added;
    for my $key (@normalized) {
        $self->run_ssh_add($key);
        push @added, $key;
    }

    return {
        mode     => 'add',
        agent    => $self->agent_socket,
        added    => \@added,
        registry => $self->keys_file,
    };
}

sub collector_check {
    my ($self) = @_;
    my @keys = $self->read_keys;
    my @loaded = $self->loaded_key_fingerprints;
    my %loaded = map { $_ => 1 } @loaded;
    my @missing;

    for my $key (@keys) {
        my $fingerprint = $self->key_fingerprint($key);
        push @missing, $key if !$fingerprint || !$loaded{$fingerprint};
    }

    if (@missing) {
        if ( $self->is_interactive ) {
            for my $key (@missing) {
                $self->explain_collector_prompt($key);
                $self->run_ssh_add($key);
            }
        }
        return {
            mode     => 'collector',
            status   => $self->is_interactive ? 'prompted' : 'missing',
            agent    => $self->agent_socket,
            loaded   => scalar(@keys) - scalar(@missing),
            missing  => \@missing,
            registry => $self->keys_file,
        };
    }

    return {
        mode     => 'collector',
        status   => 'ok',
        agent    => $self->agent_socket,
        loaded   => scalar(@keys),
        missing  => [],
        registry => $self->keys_file,
    };
}

sub ensure_agent {
    my ($self) = @_;
    my $socket = $self->agent_socket;
    my $current = $self->{env}{SSH_AUTH_SOCK} || $ENV{SSH_AUTH_SOCK} || $self->read_agent_env || q{};

    if ( $current ne q{} && $self->ssh_add_list_rc($current) != 2 ) {
        $self->write_agent_env($current);
        return $current;
    }

    if ( -S $socket && $self->ssh_add_list_rc($socket) != 2 ) {
        $self->set_auth_sock($socket);
        $self->write_agent_env($socket);
        return $socket;
    }

    unlink $socket if -e $socket;
    $self->start_agent($socket);
    $self->set_auth_sock($socket);
    $self->write_agent_env($socket);
    return $socket;
}

sub ssh_add_list_rc {
    my ( $self, $socket ) = @_;
    my %env = ( %{ $self->{env} || \%ENV }, SSH_AUTH_SOCK => $socket );
    return $self->system_with_env( \%env, 'ssh-add', '-l' );
}

sub start_agent {
    my ( $self, $socket ) = @_;
    make_path( dirname($socket) );
    my ( $stdout, $stderr, $exit ) = $self->capture_command( 'ssh-agent', '-a', $socket, '-s' );
    die "ssh-agent failed: $stderr" if $exit != 0;
    return $stdout;
}

sub run_ssh_add {
    my ( $self, $key ) = @_;
    my %env = ( %{ $self->{env} || \%ENV }, SSH_AUTH_SOCK => $self->agent_socket );
    my $exit = $self->system_with_env( \%env, 'ssh-add', $self->expand_key_path($key) );
    die "ssh-add failed for $key" if $exit != 0;
    return 1;
}

sub loaded_key_fingerprints {
    my ($self) = @_;
    my %env = ( %{ $self->{env} || \%ENV }, SSH_AUTH_SOCK => $self->agent_socket );
    my ( $stdout, undef, $exit ) = $self->capture_with_env( \%env, 'ssh-add', '-l' );
    return () if $exit != 0;
    my @fingerprints;
    for my $line ( split /\n/, $stdout ) {
        push @fingerprints, $1 if $line =~ /\b(SHA256:[^\s]+)/;
    }
    return @fingerprints;
}

sub key_fingerprint {
    my ( $self, $key ) = @_;
    $key = $self->expand_key_path($key);
    my $pub = -f "$key.pub" ? "$key.pub" : $key;
    return if !-f $pub;
    my ( $stdout, undef, $exit ) = $self->capture_command( 'ssh-keygen', '-lf', $pub );
    return if $exit != 0;
    return $1 if $stdout =~ /\b(SHA256:[^\s]+)/;
    return;
}

sub explain_collector_prompt {
    my ( $self, $key ) = @_;
    my $fh = $self->{stderr_fh} || \*STDERR;
    print {$fh} "Developer Dashboard ssh.door-opener found that $key is remembered but not loaded in ssh-agent.\n";
    print {$fh} "Enter the key passphrase now so later ssh connections do not interrupt your workflow.\n";
    return 1;
}

sub remember_keys {
    my ( $self, @keys ) = @_;
    my @existing = $self->read_keys;
    my %seen = map { $_ => 1 } @existing;
    for my $key (@keys) {
        next if $seen{$key}++;
        push @existing, $key;
    }
    $self->write_keys(@existing);
    return @existing;
}

sub read_keys {
    my ($self) = @_;
    my $file = $self->keys_file;
    return () if !-f $file;
    open my $fh, '<', $file or die "Unable to read $file: $!";
    my @keys = grep { $_ ne q{} && $_ !~ /^#/ } map { chomp; $_ } <$fh>;
    close $fh;
    return @keys;
}

sub write_keys {
    my ( $self, @keys ) = @_;
    my $file = $self->keys_file;
    make_path( dirname($file) );
    open my $fh, '>', $file or die "Unable to write $file: $!";
    print {$fh} "$_\n" for @keys;
    close $fh;
    return 1;
}

sub normalize_key_path {
    my ( $self, $key ) = @_;
    die 'Missing key path' if !defined $key || $key eq q{};
    return $key if $key =~ /^~\//;
    return $key if File::Spec->file_name_is_absolute($key);
    return '~/.ssh/' . $key;
}

sub expand_key_path {
    my ( $self, $key ) = @_;
    return $self->home . substr( $key, 1 ) if defined $key && $key =~ /^~\//;
    return $key;
}

sub default_key {
    my ($self) = @_;
    for my $name (qw(id_rsa id_ed25519)) {
        my $path = $self->home_path( '.ssh', $name );
        return "~/.ssh/$name" if -f $path;
    }
    return;
}

sub ensure_skill_layout {
    my ($self) = @_;
    make_path( $self->config_ssh_dir );
    make_path( $self->state_dir );
    return 1;
}

sub ensure_ssh_config_bridge {
    my ($self) = @_;
    my $ssh_dir = $self->home_path('.ssh');
    make_path($ssh_dir);
    my $include = $self->managed_ssh_include_file;
    open my $inc_fh, '>', $include or die "Unable to write $include: $!";
    print {$inc_fh} "Host *\n";
    print {$inc_fh} "  IdentityAgent ", $self->active_agent_socket, "\n";
    close $inc_fh;

    my $config = $self->home_path( '.ssh', 'config' );
    my $line = 'Include ~/.ssh/developer-dashboard-ssh-agent.conf';
    my $content = q{};
    if ( -f $config ) {
        open my $cfg_fh, '<', $config or die "Unable to read $config: $!";
        local $/;
        $content = <$cfg_fh>;
        close $cfg_fh;
    }
    return 1 if $content =~ /^\Q$line\E\s*$/m;

    open my $cfg_out, '>>', $config or die "Unable to append $config: $!";
    print {$cfg_out} "\n" if $content ne q{} && $content !~ /\n\z/;
    print {$cfg_out} "# Developer Dashboard ssh skill managed include\n";
    print {$cfg_out} "$line\n";
    close $cfg_out;
    return 1;
}

sub write_agent_env {
    my ( $self, $socket ) = @_;
    my $file = $self->agent_env_file;
    make_path( dirname($file) );
    open my $fh, '>', $file or die "Unable to write $file: $!";
    print {$fh} "export SSH_AUTH_SOCK='$socket'\n";
    close $fh;
    return 1;
}

sub read_agent_env {
    my ($self) = @_;
    my $file = $self->agent_env_file;
    return if !-f $file;
    open my $fh, '<', $file or die "Unable to read $file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    return $1 if $content =~ /SSH_AUTH_SOCK='([^']+)'/;
    return $1 if $content =~ /SSH_AUTH_SOCK=([^;\s]+)/;
    return;
}

sub active_agent_socket {
    my ($self) = @_;
    return $self->{env}{SSH_AUTH_SOCK} || $ENV{SSH_AUTH_SOCK} || $self->agent_socket;
}

sub set_auth_sock {
    my ( $self, $socket ) = @_;
    $self->{env}{SSH_AUTH_SOCK} = $socket;
    $ENV{SSH_AUTH_SOCK} = $socket if !$self->{no_global_env};
    return $socket;
}

sub system_with_env {
    my ( $self, $env, @cmd ) = @_;
    return $self->{system}->( $env, @cmd ) if $self->{system};
    local %ENV = %{$env};
    system @cmd;
    return $? >> 8;
}

sub capture_with_env {
    my ( $self, $env, @cmd ) = @_;
    return $self->{capture}->( $env, @cmd ) if $self->{capture};
    local %ENV = %{$env};
    return $self->capture_command(@cmd);
}

sub capture_command {
    my ( $self, @cmd ) = @_;
    return $self->{capture_command}->(@cmd) if $self->{capture_command};
    my $stdout = qx{@cmd 2>/tmp/ssh-skill-capture.err};
    my $exit = $? >> 8;
    my $stderr = q{};
    if ( open my $err, '<', '/tmp/ssh-skill-capture.err' ) {
        local $/;
        $stderr = <$err>;
        close $err;
    }
    return ( $stdout, $stderr, $exit );
}

sub is_interactive {
    my ($self) = @_;
    return $self->{interactive} if exists $self->{interactive};
    return -t STDIN ? 1 : 0;
}

sub keys_file {
    my ($self) = @_;
    return File::Spec->catfile( $self->config_ssh_dir, 'keys.txt' );
}

sub config_ssh_dir {
    my ($self) = @_;
    return File::Spec->catdir( $self->config_root, 'ssh' );
}

sub config_root {
    my ($self) = @_;
    return $ENV{DEVELOPER_DASHBOARD_SKILL_CONFIG_ROOT} if $ENV{DEVELOPER_DASHBOARD_SKILL_CONFIG_ROOT};
    return File::Spec->catdir( $self->skill_root, 'config' );
}

sub state_dir {
    my ($self) = @_;
    return $ENV{DEVELOPER_DASHBOARD_SKILL_STATE_ROOT} if $ENV{DEVELOPER_DASHBOARD_SKILL_STATE_ROOT};
    return File::Spec->catdir( $self->skill_root, 'state' );
}

sub skill_root {
    my ($self) = @_;
    return $self->{skill_root} if $self->{skill_root};
    return $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} if $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT};
    return getcwd() if -d File::Spec->catdir( getcwd(), 'cli' ) && -d File::Spec->catdir( getcwd(), 'lib' );
    return File::Spec->catdir( dirname( dirname( dirname($MODULE_FILE) ) ) );
}

sub home {
    my ($self) = @_;
    return $self->{home} || $ENV{HOME} || die 'HOME is required';
}

sub home_path {
    my ( $self, @parts ) = @_;
    return File::Spec->catfile( $self->home, @parts );
}

sub agent_dir {
    my ($self) = @_;
    return File::Spec->catdir( $self->home, '.developer-dashboard', 'ssh-agent' );
}

sub agent_socket {
    my ($self) = @_;
    return File::Spec->catfile( $self->agent_dir, 'agent.sock' );
}

sub agent_env_file {
    my ($self) = @_;
    return File::Spec->catfile( $self->agent_dir, 'agent.env' );
}

sub managed_ssh_include_file {
    my ($self) = @_;
    return $self->home_path( '.ssh', 'developer-dashboard-ssh-agent.conf' );
}

1;
