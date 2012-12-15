#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper
package server::linkage;

use warnings;
use strict;

use utils qw[conf log2 gv lconf];

use IO::Async::Stream;
use IO::Async::Timer::Countdown;

# connect to a server in the configuration
sub connect_server {
    my $server_name = shift;

    # make sure we at least have some configuration information about the server.
    unless ($ircd::conf->has_block(['connect', $sever_name])) {
        log2("attempted to connect to nonexistent server: $server_name");
        return;
    }
    
    # then, ensure that the server is not connected already.
    if (server::lookup_by_name($server_name)) {
        log2("attempted to connect an already connected server: $server_name");
        return;
    }

    my %serv = $ircd::conf->(['connect', $server_name]);

    # create the socket
    my $socket = IO::Socket::IP->new(
        PeerAddr => $serv{address},
        PeerPort => $serv{port},
        Proto    => 'tcp'
    );

    if (!$socket) {
        log2("could not connect to server $server_name: ".($! ? $! : $@));
        return;
    }

    log2("connection established to server $server_name");

    my $stream = IO::Async::Stream->new(
        read_handle  => $socket,
        write_handle => $socket
    );

    # create connection object 
    my $conn = connection->new($stream);

    $stream->configure(
        read_all       => 0,
        read_len       => POSIX::BUFSIZ,
        on_read        => \&ircd::handle_data,
        on_read_eof    => sub { _end($conn, $stream, $server_name, 'connection closed')   },
        on_write_eof   => sub { _end($conn, $stream, $server_name, 'connection closed')   },
        on_read_error  => sub { _end($conn, $stream, $server_name, 'read error :'.$_[1])  },
        on_write_error => sub { _end($conn, $stream, $server_name, 'write error: '.$_[1]) }
    );

    $main::loop->add($stream);

    # send server credentials.
    $conn->send(sprintf 'SERVER %s %s %s %s :%s',
        gv('SERVER', 'sid'),
        gv('SERVER', 'name'),
        gv('PROTO'),
        gv('VERSION'),
        gv('SERVER', 'desc')
    );

    $conn->send("PASS $serv{send_password}");

    $conn->{sent_creds} = 1;
    $conn->{want}       = $server_name;

    return $conn;

}

sub _end {
    my ($conn, $stream, $server_name, $reason) = @_;
    $conn->done('write error: '.$_[1]);
    $stream->close_now;
    
    # if we have an autoconnect_timer for this server, start a connection timer.
    my $timeout = lconf('connect', $server_name, 'auto_timeout');
    if ($timeout) {
        log2("going to attempt to connect to server $server_name in $timeout seconds.");
        
        # start the timer.
        my $timer = IO::Async::Timer::Periodic->new( 
            delay     => $timeout,
            on_expire => sub { connect_server($server_name) }
        );
        
        $main::loop->add($timer);
        $timer->start;
        
    }
    
    # if we don't, that's all - we're done.
    
}

1