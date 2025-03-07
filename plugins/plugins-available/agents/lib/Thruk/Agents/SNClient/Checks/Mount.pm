package Thruk::Agents::SNClient::Checks::Mount;

use warnings;
use strict;

use Thruk::Agents::SNClient ();
use Thruk::Utils::Agents ();

=head1 NAME

Thruk::Agents::SNClient::Checks::Mount - returns mount checks for snclient

=head1 METHODS

=cut

##########################################################

=head2 get_checks

    get_checks()

returns snclient checks

=cut
sub get_checks {
    my($self, $c, $inventory, $hostname, $password, $section) = @_;
    my $checks = [];

    return unless $inventory->{'mount'};

    my $disabled_config = Thruk::Agents::SNClient::get_disabled_config($c, 'mount', {
            'fstype' => '= cdfs',
            'mount'  => '~ ^(/sys/run|/dev|/proc|/var/lib/docker|/Volumes/com.apple.TimeMachine.localsnapshots|/Volumes/.timemachine|/private/tmp/)',
    });
    for my $mount (@{$inventory->{'mount'}}) {
        $mount->{'fstype'} = lc($mount->{'fstype'} // '');
        push @{$checks}, {
            'id'       => 'mount.'.Thruk::Utils::Agents::to_id($mount->{'mount'}),
            'name'     => 'mount '.$mount->{'mount'},
            'check'    => 'check_mount',
            'args'     => { "mount" => $mount->{'mount'}, "options" => $mount->{'options'}, "fstype" => $mount->{'fstype'} },
            'parent'   => 'agent version',
            'info'     => $mount,
            'disabled' => Thruk::Utils::Agents::check_disable($mount, $disabled_config, 'mount'),
            'noperf'   => 1,
        };
    }

    return $checks;
}

##########################################################

1;
