# Copyright (c) 2014, Mitchell Cooper
package API::Module::Core::OperNotices;
 
use warnings;
use strict;
 
use utils qw(log2 conf v);

my %notices = (

    new_connection          => '%s (%d)',
    connection_terminated   => '%s (%s)',

    new_user    => '%s (%s@%s) [%s] on %s',
    user_quit   => '%s (%s@%s) [%s] from %s (%s)',
    user_opered => '%s (%s@%s) [%s] gained flags on %s: %s',

    new_server      => '%s (%d) ircd %s, proto %s [%s] parent: %s',
    server_quit     => '%s (%d) parent %s (%s)',
    server_burst    => '%s (%s) is bursting information',
    server_endburst => '%s (%s) finished burst, %d seconds elapsed'

);

our $mod = API::Module->new(
    name        => 'OperNotices',
    version     => $API::Module::Core::VERSION,
    description => 'the core set of oper notices',
    requires    => ['OperNotices'],
    initialize  => \&init
);
 
sub init {

    $mod->register_oper_notice(
        name    => $_,
        format  => $notices{$_}
    ) || return foreach keys %notices;
    
    undef %notices;
    return 1;
}

$mod
