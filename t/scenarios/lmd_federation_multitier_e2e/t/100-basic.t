use warnings;
use strict;
use Cpanel::JSON::XS;
use HTML::Entities;
use Test::More;

BEGIN {
    plan skip_all => 'backends required' if(!-s 'thruk_local.conf' and !defined $ENV{'PLACK_TEST_EXTERNALSERVER_URI'});
    plan tests => 294;
}


BEGIN {
    use lib('t');
    require TestUtils;
    import TestUtils;
}

###############################################################################
TestUtils::test_page(
    'url'    => '/thruk/cgi-bin/status.cgi?hostgroup=all&style=hostdetail',
    'like'   => [
                '"total":12', '"disabled":0', '"up":12', ,'"down":0',
            ],
);

###############################################################################
# fetch backend ids
my $test = TestUtils::test_page(
    'url'    => '/thruk/cgi-bin/extinfo.cgi?type=0&view_mode=json',
    'like'   => [
                'peer_addr',
                'https://127.0.0.3:60443/demo/thruk/',
                'data_source_version',
            ],
);
my $procinfo = Cpanel::JSON::XS::decode_json($test->{'content'});
my $ids      = {map { $_->{'peer_name'} => $_->{'peer_key'} } values %{$procinfo}};
is(scalar keys %{$ids}, 12, 'got backend ids') || die("all backends required");
ok(defined $ids->{'tier1a'}, 'got backend ids II');

###############################################################################
# force reschedule checks
for my $hst (sort keys %{$ids}) {
    TestUtils::test_page(
        'url'    => '/thruk/r/hosts/'.$hst.'/cmd/schedule_forced_host_check',
        'method' => 'POST',
        'like'   => [ 'Command successfully submitted' ],
    );
    my @svc = qw/Ping Load/;
    if($hst eq 'tier3c') {
        @svc = qw/ping4 disk/;
    }
    for my $svc (@svc) {
        TestUtils::test_page(
            'url'    => '/thruk/r/services/'.$hst.'/'.$svc.'/cmd/schedule_forced_svc_check',
            'method' => 'POST',
            'like'   => [ 'Command successfully submitted' ],
        );
    }
}

###############################################################################
# send muliple commands to sub peers
TestUtils::test_page(
    'url'    => '/thruk/cgi-bin/cmd.cgi',
    'post'   => {
        'referer'           => 'status.cgi',
        'selected_services' => 'tier3b;Load;e984d;e984d,tier3b;Ping;e984d',
        'selected_hosts'    => '',
        'quick_command'     => '1',
        'start_time'        => time(),
    },
    'like'   => [ 'Commands successfully submitted' ],
    'follow' => 1,
);


###############################################################################
TestUtils::test_command({
    cmd     => './script/thruk selfcheck lmd',
    like => ['/lmd running with pid/',
             '/12\/12 backends online/',
            ],
    exit    => 0,
});

###############################################################################
