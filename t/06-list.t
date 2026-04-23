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
    my $capture = $args{capture} || sub {
        my ( $env, @cmd ) = @_;
        return ( $args{loaded} || q{}, q{}, 0 ) if $cmd[0] eq 'ssh-add' && $cmd[1] eq '-l';
        return ( q{}, q{}, 0 );
    };
    my $runner = SSH::Add->new(
        home            => $home,
        skill_root      => $root,
        env             => {},
        no_global_env   => 1,
        capture         => $capture,
        capture_command => sub {
            my (@cmd) = @_;
            return ( "256 SHA256:key1 ~/.ssh/work.pub (ED25519)\n", q{}, 0 )
              if $cmd[0] eq 'ssh-keygen' && $cmd[2] =~ /work/;
            return ( "256 SHA256:key2 ~/.ssh/personal.pub (ED25519)\n", q{}, 0 )
              if $cmd[0] eq 'ssh-keygen' && $cmd[2] =~ /personal/;
            return ( "SSH_AUTH_SOCK=$home/.ssh/ssh-agent/agent.sock; export SSH_AUTH_SOCK;\n", q{}, 0 );
        },
    );
    return ( $runner, $home, $root );
}

{
    my ( $runner, $home ) = harness( loaded => "256 SHA256:key1 card\n" );
    for my $name (qw(work personal)) {
        open my $fh, '>', File::Spec->catfile( $home, '.ssh', "$name.pub" ) or die $!;
        close $fh;
    }
    $runner->write_keys(qw(~/.ssh/work ~/.ssh/personal ~/.ssh/missing));
    my $result = $runner->execute_list('-o', 'json');
    is( $result->{mode}, 'list', 'json list mode is returned' );
    is( $result->{output}, 'json', 'json output mode is recorded' );
    is( scalar @{ $result->{keys} }, 3, 'all managed keys are listed' );
    is( $result->{keys}[0]{status}, 'loaded', 'loaded key is marked loaded' );
    is( $result->{keys}[1]{status}, 'not-loaded', 'known but unloaded key is marked not loaded' );
    is( $result->{keys}[2]{status}, 'missing-file', 'missing key file is marked missing' );
    is( $result->{keys}[0]{file}, File::Spec->catfile( $home, '.ssh', 'work' ), 'home-relative file path is expanded' );
}

{
    my ( $runner, $home ) = harness( loaded => "256 SHA256:key1 card\n" );
    open my $fh, '>', File::Spec->catfile( $home, '.ssh', 'work.pub' ) or die $!;
    close $fh;
    $runner->write_keys('~/.ssh/work');
    my $result = $runner->execute_list;
    is( $result->{output}, 'table', 'table is default output mode' );
    my $table = $runner->render_list_table( $result->{keys} );
    like( $table, qr/^KEY\s+STATUS\s+FILE\s+FINGERPRINT/m, 'table has expected header' );
    like( $table, qr/~\/\.ssh\/work\s+loaded\s+\Q$home\E\/\.ssh\/work\s+SHA256:key1/, 'table includes key status file and fingerprint' );
}

{
    my ( $runner, $home ) = harness();
    open my $fh, '>', File::Spec->catfile( $home, '.ssh', 'work.pub' ) or die $!;
    close $fh;
    $runner->{env}{SSH_AUTH_SOCK} = '/actual/socket';
    $runner->write_keys('~/.ssh/work');
    $runner->{capture} = sub {
        my ( $env, @cmd ) = @_;
        return ( "256 SHA256:key1 card\n", q{}, 0 ) if $cmd[0] eq 'ssh-add' && $cmd[1] eq '-l' && $env->{SSH_AUTH_SOCK} eq '/actual/socket';
        return ( q{}, q{}, 2 );
    };
    my $result = $runner->execute_list('-o', 'json');
    is( $result->{agent}, '/actual/socket', 'list mode reports the active socket' );
    is( $result->{keys}[0]{status}, 'loaded', 'list mode reads loaded fingerprints from the active socket' );
}

{
    my ( $runner ) = harness();
    like( eval { $runner->execute_list('-o'); 1 } ? q{} : $@, qr/Missing output format/, 'missing output value is rejected' );
    like( eval { $runner->execute_list('-o', 'yaml'); 1 } ? q{} : $@, qr/Unsupported output format/, 'unsupported output value is rejected' );
    like( eval { $runner->execute_list('--bad'); 1 } ? q{} : $@, qr/Unsupported option/, 'unsupported list option is rejected' );
}

{
    my ( $runner, $home ) = harness( loaded => "256 SHA256:key1 card\n" );
    open my $fh, '>', File::Spec->catfile( $home, '.ssh', 'work.pub' ) or die $!;
    close $fh;
    $runner->write_keys('~/.ssh/work');
    my $out_file = File::Spec->catfile( $home, 'list.json' );
    open my $oldout, '>&', \*STDOUT or die $!;
    open STDOUT, '>', $out_file or die $!;
    my $code = $runner->main_list('-o', 'json');
    open STDOUT, '>&', $oldout or die $!;
    is( $code, 0, 'main_list returns zero for json output' );
    my $decoded = decode_json( _slurp($out_file) );
    is( $decoded->{keys}[0]{status}, 'loaded', 'main_list prints json status' );
}

{
    my ( $runner, $home ) = harness( loaded => "256 SHA256:key1 card\n" );
    open my $fh, '>', File::Spec->catfile( $home, '.ssh', 'work.pub' ) or die $!;
    close $fh;
    $runner->write_keys('~/.ssh/work');
    my $out_file = File::Spec->catfile( $home, 'list.table' );
    open my $oldout, '>&', \*STDOUT or die $!;
    open STDOUT, '>', $out_file or die $!;
    my $code = $runner->main_list;
    open STDOUT, '>&', $oldout or die $!;
    is( $code, 0, 'main_list returns zero for table output' );
    like( _slurp($out_file), qr/^KEY\s+STATUS\s+FILE\s+FINGERPRINT/m, 'main_list prints table by default' );
}

{
    my $code = SSH::Add->main_list('--bad');
    is( $code, 2, 'main_list returns nonzero for bad option' );
}

sub _slurp {
    my ($file) = @_;
    open my $fh, '<', $file or die $!;
    local $/;
    return <$fh>;
}

done_testing;
