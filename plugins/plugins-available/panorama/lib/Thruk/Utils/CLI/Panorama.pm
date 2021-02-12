package Thruk::Utils::CLI::Panorama;

=head1 NAME

Thruk::Utils::CLI::Panorama - Panorama CLI module

=head1 DESCRIPTION

The panorama command manages panorama dashboards from the command line.

=head1 SYNOPSIS

  Usage: thruk [globaloptions] panorama [command]

=head1 OPTIONS

=over 4

=item B<help>

    print help and exit

=item B<command>

    available commands are:

      - clean           remove empty dashboards
      - json <nr>       load and return given dashboard in json format
      - trim <nr|file>  trim specified dashboard with given options
            --remove-panel-backends     remove backends for all icons so they inherit them from the dashboard

=back

=cut

use warnings;
use strict;
use Thruk::Utils::Log qw/:all/;
use Cpanel::JSON::XS qw/encode_json/;
use Getopt::Long ();

##############################################

=head1 METHODS

=head2 cmd

    cmd([ $options ])

=cut
sub cmd {
    my($c, $action, $commandoptions, $data, $src, $global_options) = @_;
    $c->stats->profile(begin => "_cmd_panorama($action)");

    if(!$c->check_user_roles('authorized_for_admin')) {
        return("ERROR - authorized_for_admin role required", 1);
    }

    if(!$c->config->{'use_feature_panorama'}) {
        return("ERROR - panorama dashboard addon is disabled\n", 1);
    }

    if(!Thruk::Utils::CLI::load_module("Thruk::Utils::Panorama")) {
        return("panorama plugin is disabled.\n", 1);
    }

    # parse options
    my $opt = {
      'remove-panel-backends' => undef,
    };
    Getopt::Long::Configure('no_ignore_case');
    Getopt::Long::Configure('bundling');
    Getopt::Long::Configure('pass_through');
    Getopt::Long::GetOptionsFromArray($commandoptions,
       "remove-panel-backends" => \$opt->{'remove-panel-backends'},
    ) or do {
        return(Thruk::Utils::CLI::get_submodule_help(__PACKAGE__));
    };

    my $command = shift @{$commandoptions} || 'help';
    my($rc, $output) = (0, "");
    if($command eq 'clean' || $command eq 'clean_dashboards') {
        $c->stash->{'is_admin'} = 1;
        $c->{'panorama_var'}    = $c->config->{'var_path'}.'/panorama';
        my $num = Thruk::Utils::Panorama::clean_old_dashboards($c);
        $output = "OK - cleaned up $num old dashboards\n";
    }
    elsif($command eq 'json') {
        my $nr = shift @{$commandoptions};
        return(Thruk::Utils::CLI::get_submodule_help(__PACKAGE__)) unless defined $nr;
        my $file;
        if(-e $nr) {
            $file = $nr;
            $nr   = -1;
        }
        my $dashboard = Thruk::Utils::Panorama::load_dashboard($c, $nr, undef, $file);
        if($dashboard) {
            $output = encode_json($dashboard);
            $output .= "\n";
        } else {
            $rc = 1;
        }
    }
    elsif($command eq 'trim') {
        return(Thruk::Utils::CLI::get_submodule_help(__PACKAGE__)) if scalar @{$commandoptions} == 0;
        for my $nr (@{$commandoptions}) {
            my $file;
            if(-e $nr) {
                $file = $nr;
                $nr   = -1;
            }
            my $dashboard = Thruk::Utils::Panorama::load_dashboard($c, $nr, undef, $file);
            if(!$dashboard) {
                _fatal("cannot open dashboard: ".$nr);
            }
            _info("trim dashboard: ".$dashboard->{'file'});
            if($dashboard->{'scripted'}) {
                _info("  - skipping scripted dashboard");
                next;
            }
            if($dashboard->{'readonly'}) {
                _info("  - skipping readonly dashboard");
                next;
            }
            my $changed = 0;
            if($opt->{'remove-panel-backends'}) {
                _info("  - removing panel backends");
                for my $p (sort keys %{$dashboard}) {
                    next unless $p =~ m/^panlet_/mx;
                    _debug("    - ".$p);
                    my $panel = $dashboard->{$p};
                    if($panel->{'xdata'}->{'general'} && $panel->{'xdata'}->{'general'}->{'backends'}) {
                        $panel->{'xdata'}->{'general'}->{'backends'} = [];
                        $changed++;
                    }
                }
            }
            if($changed) {
                Thruk::Utils::Panorama::save_dashboard($c, $dashboard);
                _info("    - changes saved");
            } else {
                _info("    - no changes");
            }
        }
    } else {
        return(Thruk::Utils::CLI::get_submodule_help(__PACKAGE__));
    }

    $c->stats->profile(end => "_cmd_panorama($action)");
    return($output, $rc);
}

##############################################

=head1 EXAMPLES

Clean empty dashboards

  %> thruk dashboard clean

=cut

1;
