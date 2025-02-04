use warnings;
use strict;
use Log::Log4perl qw(:easy);
use Test::More;

use Thruk::Config 'noautoload';
use Thruk::Utils ();

BEGIN {
    plan skip_all => 'internal test only' if defined $ENV{'PLACK_TEST_EXTERNALSERVER_URI'};
    plan skip_all => 'backends required' if(!-s 'thruk_local.conf' and !defined $ENV{'PLACK_TEST_EXTERNALSERVER_URI'});
    plan tests => 46;
}

BEGIN {
    use lib('t');
    require TestUtils;
    import TestUtils;
    $ENV{'THRUK_KEEP_CONTEXT'} = 1;
}

################################################################################
# initialize empty pool
use_ok("Thruk::Backend::Pool");
my $p = Thruk::Backend::Pool->new();
isa_ok($p, 'Thruk::Backend::Pool');

# initialize backend manager
use_ok("Thruk::Backend::Manager");
my $b = Thruk::Backend::Manager->new($p);
isa_ok($b, 'Thruk::Backend::Manager');

my $c = TestUtils::get_c();

Log::Log4perl->easy_init($INFO);
my $logger = Log::Log4perl->get_logger();

my $disabled_backends = $b->disable_hidden_backends();
$b->disable_backends($disabled_backends);

################################################################################
# get testdata
my($hostname,$servicename) = TestUtils::get_test_service();

################################################################################
# expand host command
my $hosts = $b->get_hosts( filter => [ { 'name' => $hostname } ] );
ok(scalar @{$hosts} > 0, 'got host data');

my $cmd = $b->expand_command(
    'host' => $hosts->[0],
);

isnt($cmd, undef, 'got expanded command for host');
isnt($cmd->{'line_expanded'}, undef, 'expanded command: '.$cmd->{'line_expanded'});
unlike($cmd->{'line_expanded'}, qr/HOSTNAME/, 'expanded command line must not contain HOSTNAME');
unlike($cmd->{'line_expanded'}, qr/HOSTALIAS/, 'expanded command line must not contain HOSTALIAS');
unlike($cmd->{'line_expanded'}, qr/HOSTADDRESS/, 'expanded command line must not contain HOSTADDRESS');

################################################################################
# expand service command
my $services = $b->get_services( filter => [ { 'host_name' => $hostname, 'description' => $servicename } ] );
ok(scalar @{$services} > 0, 'got service data');

$cmd = $b->expand_command(
    'host'    => $hosts->[0],
    'service' => $services->[0],
);

isnt($cmd, undef, 'got expanded command for service');
isnt($cmd->{'line_expanded'}, undef, 'expanded command: '.$cmd->{'line_expanded'});
unlike($cmd->{'line_expanded'}, qr/HOSTNAME/, 'expanded command line must not contain HOSTNAME');
unlike($cmd->{'line_expanded'}, qr/HOSTALIAS/, 'expanded command line must not contain HOSTALIAS');
unlike($cmd->{'line_expanded'}, qr/HOSTADDRESS/, 'expanded command line must not contain HOSTADDRESS');
unlike($cmd->{'line_expanded'}, qr/SERVICEDESC/, 'expanded command line must not contain SERVICEDESC');

################################################################################
# now set a ressource file
################################################################################
# read resource file
my $expected_resource = {
    '$USER1$'     => '/tmp',
    '$USER2$'     => 'test3',
    '$PLUGINDIR$' => '/usr/local/plugins',
};
my $res = Thruk::Utils::read_resource_file('t/data/resource.cfg');
is_deeply($res, $expected_resource, 'reading resource file');

################################################################################
# set resource file
$c->{'config'}->{'expand_user_macros'} = [];
$c->{'config'}->{'resource_file'} = 't/data/resource.cfg';
for my $backend ( @{$p->{'objects'}} ) {
    if(defined $backend->{'resource_file'}) {
        $backend->{'resource_file'} = $c->{'config'}->{'resource_file'};
    }
}
$cmd = $b->expand_command(
    'host'    => $hosts->[0],
    'command' => {
        'name' => 'check_test',
        'line' => '$USER1$/check_test -H $HOSTNAME$'
    },
);
is($cmd->{'line_expanded'}, '/tmp/check_test -H '.$hosts->[0]->{'name'}, 'expanded command: '.$cmd->{'line_expanded'});
is($cmd->{'line'}, $hosts->[0]->{'check_command'}, 'host command is: '.$hosts->[0]->{'check_command'});
is($cmd->{'note'}, '', 'note should be empty');

################################################################################
$cmd = $b->expand_command(
    'host'    => $hosts->[0],
    'command' => {
        'name' => 'check_test',
        'line' => '$PLUGINDIR$/check_test -H $HOSTNAME$'
    },
);
is($cmd->{'line_expanded'}, '/usr/local/plugins/check_test -H '.$hosts->[0]->{'name'}, 'expanded command: '.$cmd->{'line_expanded'});
is($cmd->{'line'}, $hosts->[0]->{'check_command'}, 'host command is: '.$hosts->[0]->{'check_command'});
is($cmd->{'note'}, '', 'note should be empty');

################################################################################
$cmd = $b->expand_command(
    'host'    => {
        'state'             => 0,
        'last_state_change' => time(),
        'check_command'     => 'check_test!',
    },
    'command' => {
        'name' => 'check_test',
        'line' => '$USER1$/check_test $ARG1$'
    },
);
is($cmd->{'line_expanded'}, '/tmp/check_test ', 'expanded command: '.$cmd->{'line_expanded'});
is($cmd->{'note'}, '', 'note should be empty');

################################################################################
# set expand user macros
$c->{'config'}->{'expand_user_macros'} = ["NONE"];
$cmd = $b->expand_command(
    'host'    => $hosts->[0],
    'command' => {
        'name' => 'check_test',
        'line' => '$PLUGINDIR$/check_test -H $HOSTNAME$ -p $USER2$'
    },
);
is($cmd->{'line_expanded'}, '$PLUGINDIR$/check_test -H '.$hosts->[0]->{'name'}.' -p $USER2$', 'expanded command: '.$cmd->{'line_expanded'});
is($cmd->{'line'}, $hosts->[0]->{'check_command'}, 'host command is: '.$hosts->[0]->{'check_command'});

################################################################################
# set expand user macros
$c->{'config'}->{'expand_user_macros'} = ["PLUGINDIR"];
$cmd = $b->expand_command(
    'host'    => $hosts->[0],
    'command' => {
        'name' => 'check_test',
        'line' => '$PLUGINDIR$/check_test -H $HOSTNAME$ -p $USER2$'
    },
);
is($cmd->{'line_expanded'}, '/usr/local/plugins/check_test -H '.$hosts->[0]->{'name'}.' -p $USER2$', 'expanded command: '.$cmd->{'line_expanded'});
is($cmd->{'line'}, $hosts->[0]->{'check_command'}, 'host command is: '.$hosts->[0]->{'check_command'});

################################################################################
# set expand user macros
$c->{'config'}->{'expand_user_macros'} = ["PLUGINDIR", "USER*"];
$cmd = $b->expand_command(
    'host'    => $hosts->[0],
    'command' => {
        'name' => 'check_test',
        'line' => '$PLUGINDIR$/check_test -H $HOSTNAME$ -p $USER2$'
    },
);
is($cmd->{'line_expanded'}, '/usr/local/plugins/check_test -H '.$hosts->[0]->{'name'}.' -p test3', 'expanded command: '.$cmd->{'line_expanded'});
is($cmd->{'line'}, $hosts->[0]->{'check_command'}, 'host command is: '.$hosts->[0]->{'check_command'});
is($cmd->{'note'}, '', 'note should be empty');

################################################################################
# set expand user macros
$c->{'config'}->{'expand_user_macros'} = ["USER1-2"];
Thruk::Config::set_default_config($c->{'config'});
$cmd = $b->expand_command(
    'host'    => $hosts->[0],
    'command' => {
        'name' => 'check_test',
        'line' => '$USER1$/check_test -H $HOSTNAME$ -p $USER2$ $USER3$',
    },
);
is($cmd->{'line_expanded'}, '/tmp/check_test -H '.$hosts->[0]->{'name'}.' -p test3 $USER3$', 'expanded command: '.$cmd->{'line_expanded'});

################################################################################
# set expand user macros
$c->{'config'}->{'expand_user_macros'} = ["ALL"];
$cmd = $b->expand_command(
    'host'    => $hosts->[0],
    'command' => {
        'name' => 'check_test',
        'line' => '$USER1$/check_test -H $HOSTNAME$ -p $USER2$',
    },
);
is($cmd->{'line_expanded'}, '/tmp/check_test -H '.$hosts->[0]->{'name'}.' -p test3', 'expanded command: '.$cmd->{'line_expanded'});

################################################################################
# test obfuscation (from host macro)
$c->{'config'}->{'expand_user_macros'} = ["ALL"];
$cmd = $b->expand_command(
    'host'    => {(%{$hosts->[0]}, ('custom_variable_names' => ['OBFUSCATE_ME'], 'custom_variable_values' => ['password']))},
    'command' => {
        'name' => 'check_test',
        'line' => '$USER1$/check_test -H $HOSTNAME$ -p "password"',
    },
);
is($cmd->{'line_expanded'}, '/tmp/check_test -H '.$hosts->[0]->{'name'}.' -p "***"', 'expanded command: '.$cmd->{'line_expanded'});

################################################################################
# test obfuscation (from host macro)
$c->{'config'}->{'expand_user_macros'} = ["ALL"];
$cmd = $b->expand_command(
    'host'    => {(%{$hosts->[0]}, ('custom_variable_names' => ['OBFUSCATE_REGEXP'], 'custom_variable_values' => ['pas+.*ord']))},
    'command' => {
        'name' => 'check_test',
        'line' => '$USER1$/check_test -H $HOSTNAME$ -p "password"',
    },
);
is($cmd->{'line_expanded'}, '/tmp/check_test -H '.$hosts->[0]->{'name'}.' -p "***"', 'expanded command: '.$cmd->{'line_expanded'});

################################################################################
# test obfuscation (from host macro)
$c->{'config'}->{'expand_user_macros'} = ["ALL"];
$cmd = $b->expand_command(
    'host'    => {(%{$hosts->[0]}, ('custom_variable_names' => ['OBFUSCATE_STRING'], 'custom_variable_values' => ['*as+w$r/']))},
    'command' => {
        'name' => 'check_test',
        'line' => '$USER1$/check_test -H $HOSTNAME$ -p "*as+w$r/"',
    },
);
is($cmd->{'line_expanded'}, '/tmp/check_test -H '.$hosts->[0]->{'name'}.' -p "***"', 'expanded command: '.$cmd->{'line_expanded'});

################################################################################
# test base64 obfuscation (from host macro)
$c->{'config'}->{'expand_user_macros'} = ["ALL"];
$cmd = $b->expand_command(
    'host'    => {(%{$hosts->[0]}, ('custom_variable_names' => ['OBFUSCATE_ME'], 'custom_variable_values' => ['b64:cGFzc3dvcmQ=']))},
    'command' => {
        'name' => 'check_test',
        'line' => '$USER1$/check_test -H $HOSTNAME$ -p "password"',
    },
);
is($cmd->{'line_expanded'}, '/tmp/check_test -H '.$hosts->[0]->{'name'}.' -p "***"', 'expanded command: '.$cmd->{'line_expanded'});

################################################################################
# test base64 obfuscation (from host macro)
$c->{'config'}->{'expand_user_macros'} = ["ALL"];
$cmd = $b->expand_command(
    'host'    => {(%{$hosts->[0]}, ('custom_variable_names' => ['OBFUSCATE_STR'], 'custom_variable_values' => ['b64:cGFzc3dvcmQ=']))},
    'command' => {
        'name' => 'check_test',
        'line' => '$USER1$/check_test -H $HOSTNAME$ -p "password"',
    },
);
is($cmd->{'line_expanded'}, '/tmp/check_test -H '.$hosts->[0]->{'name'}.' -p "***"', 'expanded command: '.$cmd->{'line_expanded'});

################################################################################
# test obfuscation (from global config)
$c->{'config'}->{'expand_user_macros'}            = ["ALL"];
$c->{'config'}->{'commandline_obfuscate_pattern'} = ['/(\-\-password=")[^"]*(")/$1***$2/'];
$cmd = $b->expand_command(
    'host'    => $hosts->[0],
    'command' => {
        'name' => 'check_test',
        'line' => '$USER1$/check_test -H $HOSTNAME$ --password="test"',
    },
);
is($cmd->{'line_expanded'}, '/tmp/check_test -H '.$hosts->[0]->{'name'}.' --password="***"', 'expanded command: '.$cmd->{'line_expanded'});

################################################################################
# unescape shell variables
$c->{'config'}->{'expand_user_macros'} = ["PLUGINDIR"];
$cmd = $b->expand_command(
    'host'    => $hosts->[0],
    'command' => {
        'name' => 'check_test',
        'line' => '$PLUGINDIR$/check_test -H $HOSTNAME$ -p $USER2$ -x $$USER'
    },
);
is($cmd->{'line_expanded'}, '/usr/local/plugins/check_test -H '.$hosts->[0]->{'name'}.' -p $USER2$ -x $USER', 'expanded command: '.$cmd->{'line_expanded'});

################################################################################
my $res1 = Thruk::Utils::read_resource_file('t/data/resource.cfg');
my $res2 = Thruk::Utils::read_resource_file('t/data/resource2.cfg');
is_deeply($res1, $res2, 'parsing resource.cfg');
