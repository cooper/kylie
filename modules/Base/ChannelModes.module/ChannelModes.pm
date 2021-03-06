# Copyright (c) 2012-14, Mitchell Cooper
#
# @name:            "Base::ChannelModes"
# @package:         "M::Base::ChannelModes"
#
# @depends.modules+ "API::Methods"
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package M::Base::ChannelModes;

use warnings;
use strict;
use 5.010;

use utils 'cols';

our ($api, $mod, $pool, $me);

sub init {

    # register methods.
    $mod->register_module_method('register_channel_mode_block') or return;

    # module events.
    $api->on('module.unload' => \&on_unload, 'void.channel.modes');
    $api->on('module.init'   => \&module_init,   '%channel_modes');

    return 1;
}

###########################
### PROVIDED MODE TYPES ###
###########################

my %mode_types = (
    normal      => \&cmode_normal,
    banlike     => \&cmode_banlike
);

sub cmode_normal {
    my ($channel, $mode) = @_;
    return $mode->{has_basic_status};
}

sub cmode_banlike {
    my ($channel, $mode, %opts) = @_;
    _cmode_banlike(
        $opts{list},
        $opts{reply},
        $opts{show_mode},
        $channel,
        $mode
    );
}

# for banlike modes.
# not to be used directly.
#
# $list             the name used internally  (e.g. mute)
# $reply            the name used in numerics (e.g. QUIET)
# $show_letter      whether to show the letter in the RPL_ENDOF*
# $channel          channel object
# $mode             mode fire info
#
sub _cmode_banlike {
    my ($list, $reply, $show_letter, $channel, $mode) = @_;
    my $local_user = $mode->{source};
    undef $local_user if !$local_user->isa('user') || !$local_user->is_local;
    
    # local user viewing the list
    if ($local_user && !length $mode->{param}) {

        # consider the numeric reply names and whether to send the mode letter.
        my $name = uc($reply)."LIST";
        my @channel_letter = $channel->name;
        push @channel_letter, $me->cmode_letter($list) if $show_letter;

        # send each list item.
        $local_user->numeric("RPL_$name" =>
            @channel_letter,
            $_->[0],
            $_->[1]{setby},
            $_->[1]{time}
        ) foreach $channel->list_elements($list, 1);

        # end of list.
        $local_user->numeric("RPL_ENDOF$name" => @channel_letter);

        return 1;
    }

    # needs privs from this point on
    if (!$mode->{has_basic_status}) {
        $mode->{send_no_privs} = 1;
        return;
    }

    # remove prefixing colons
    $mode->{param} = cols($mode->{param});
    if (!length $mode->{param}) {
        return;
    }
    
    # removing an entry
    if (!$mode->{state}) {
        $channel->remove_from_list($list, $mode->{param});
        return 1;
    }

    # adding an entry

    # it's full! this limitation only applies to local users
    if ($local_user && $channel->list_is_full($list)) {
        $local_user->numeric(ERR_BANLISTFULL =>
            $channel->name, $mode->{param}, $list);
        return;
    }
    
    # add it
    $channel->add_to_list($list, $mode->{param},
        setby => $mode->{source}->full,
        time  => time
    );

    return 1;
}

####################
### REGISTRATION ###
####################

sub register_channel_mode_block {
    my ($mod, $event, %opts) = @_;

    # make sure all required options are present.
    foreach my $what (qw|name code|) {
        next if exists $opts{$what};
        $opts{name} ||= 'unknown';
        L("Channel mode block $opts{name} does not have '$what' option");
        return;
    }

    # register the mode block.
    $opts{name} = lc $opts{name};
    $pool->register_channel_mode_block(
        $opts{name},
        $mod->name,
        $opts{code}
    );
    
    # register stringifiers
    foreach (keys %opts) {
        next unless m/^str_(\w+)$/;
        my ($proto, $code) = ($1, $opts{$_});
        $pool->on("cmode.stringify.$opts{name}.$proto" => sub {
                my ($event, $channel, $param) = @_;
                $event->{proto}  = $proto;
                $event->{string} = $code->($channel, $param);
                $event->stop; # the first one wins
            },
            priority    => $proto eq '1459' ? 0 : 100, # 1459 comes last
            name        => $proto,
            _caller     => $mod->package
        );
    }

    D("'$opts{name}' registered");
    $mod->list_store_add('channel_modes', $opts{name});
}

sub on_unload {
    my ($mod, $event) = @_;

    # delete all mode blocks.
    $pool->delete_channel_mode_block($_, $mod->name)
      foreach $mod->list_store_items('channel_modes');

    return 1;
}

# a module is being initialized.
sub module_init {
    my $mod = shift;
    my %cmodes = $mod->get_symbol('%channel_modes');

    # register each mode block.
    foreach my $name (keys %cmodes) {
        my $hashref = $cmodes{$name};
        ref $hashref eq 'HASH' or next;

        # find the code. fall back to cmode_normal.
        my $real_code = $hashref->{code}    ||
            $mode_types{ $hashref->{type} } ||
            \&cmode_normal;


        # store it.
        $mod->register_channel_mode_block(
            name => $name,
            code => sub { $real_code->(@_, %$hashref) },
            %$hashref
        ) or return;

    }

    return 1;
}

$mod
