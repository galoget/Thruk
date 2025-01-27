use warnings;
use strict;
use File::Temp qw/tempfile/;
use Test::More;
use URI::Escape;

eval "use Test::Cmd";
plan skip_all => 'Test::Cmd required' if $@;

BEGIN {
    plan skip_all => 'backends required' if(!-s 'thruk_local.conf' and !defined $ENV{'PLACK_TEST_EXTERNALSERVER_URI'});
}

BEGIN {
    use lib('t');
    require TestUtils;
    import TestUtils;
}

require Thruk::Utils::IO;

my $BIN = defined $ENV{'THRUK_BIN'} ? $ENV{'THRUK_BIN'} : './script/thruk';
$BIN    = $BIN.' --local' unless defined $ENV{'PLACK_TEST_EXTERNALSERVER_URI'};

# get test host / hostgroup
my $host      = TestUtils::get_test_host_cli($BIN);
my $hostgroup = TestUtils::get_test_hostgroup_cli($BIN);
my @mail_like = ('/This is a multi-part message in MIME format./', '/Your report is attached./', '/To: nobody@localhost/');
my $test_pdf_reports = [{
        'name'                  => 'Host',
        'template'              => 'sla_host.tt',
        'params.sla'            => 95,
        'params.graph_min_sla'  => 90,
        'params.decimals'       => 2,
        'params.timeperiod'     => 'last12months',
        'params.host'           => $host,
        'params.breakdown'      => 'months',
        'params.unavailable'    => [ 'down', 'unreachable' ],
        'mail.like'             => [ @mail_like, '/report.pdf/' ],
    }, {
        'name'                  => 'Hostgroups by Day',
        'template'              => 'sla_hostgroup.tt',
        'params.timeperiod'     => 'last12months',
        'params.sla'            => 95,
        'params.graph_min_sla'  => 90,
        'params.decimals'       => 3,
        'params.hostgroup'      => $hostgroup,
        'params.breakdown'      => 'days',
        'params.unavailable'    => [ 'down', 'unreachable' ],
        'mail.like'             => [ @mail_like, '/report.pdf/' ],
    }, {
        'name'                  => 'Day by Months',
        'template'              => 'sla_host.tt',
        'params.host'           => $host,
        'params.sla'            => 95,
        'params.graph_min_sla'  => 90,
        'params.decimals'       => 1,
        'params.timeperiod'     => 'today',
        'params.breakdown'      => 'months',
        'params.unavailable'    => [ 'down', 'unreachable' ],
        'mail.like'             => [ @mail_like, '/report.pdf/' ],
    }, {
        'name'                  => 'Excel Report',
        'type'                  => 'xls',
        'template'              => 'report_from_url.tt',
        'params.url'            => uri_escape('status.cgi?style=hostdetail&hostgroup=all&view_mode=xls'),
        'mail.like'             => [ @mail_like, '/status.xls/' ],
    }, {
        'name'                  => 'HTML Report',
        'type'                  => 'hmtl',
        'template'              => 'report_from_url.tt',
        'params.url'            => uri_escape('status.cgi?host=all'),
        'params.minimal'        => 'yes',
        'params.js'             => 'no',
        'params.css'            => 'yes',
        'params.pdf'            => 'yes',
        'params.theme'          => 'Thruk',
        'mail.like'             => [ @mail_like, '/report.pdf/' ],
    }, {
        'name'                  => 'HTML Report',
        'type'                  => 'hmtl',
        'template'              => 'report_from_url.tt',
        'params.url'            => uri_escape('status.cgi?host=all'),
        'params.minimal'        => 'yes',
        'params.js'             => 'no',
        'params.css'            => 'yes',
        'params.pdf'            => 'no',
        'params.theme'          => 'Light',
        'mail.like'             => [ @mail_like, '/status.html/' ],
        'mail.unlike'           => [ '/<script/', '/report.pdf/' ],
    }, {
        'name'                  => 'Event Report',
        'template'              => 'eventlog.tt',
        'params.timeperiod'     => 'last24hours',
        'params.pattern'        => '',
        'params.exclude_pattern'=> '',
        'mail.like'             => [ @mail_like, '/report.pdf/' ],
    }
];

for my $report (@{$test_pdf_reports}) {
    # create report
    my $mail_like   = delete $report->{'mail.like'}   || [];
    my $mail_unlike = delete $report->{'mail.unlike'} || [];
    my $args = [];
    my $rand = int(rand(1000000));
    $report->{'desc'} = "Test Report ".$rand.' ('.$report->{'name'}.')';
    $report->{'desc'} =~ s/\s+/_/gmx;
    for my $key (keys %{$report}) {
        for my $val (ref $report->{$key} eq 'ARRAY' ? @{$report->{$key}} : $report->{$key}) {
            push @{$args}, $key.'='.$val;
        }
    }
    push @{$args}, 'to=nobody@localhost';
    TestUtils::test_command({
        cmd  => $BIN.' "/thruk/cgi-bin/reports2.cgi?action=save&report=9999&'.join('&', @{$args}).'"',
        like => ['/^OK - report updated$/'],
    });

    my $like = [];
    if(!defined $report->{'type'} or $report->{'type'} eq 'pdf') {
        $like = [ '/%PDF\-1\.4/', '/%%EOF/' ];
    }
    elsif($report->{'type'} eq 'xls') {
        $like = [ '/Arial1/', '/Tahoma1/' ];
    }
    elsif($report->{'type'} eq 'html') {
        $like = [ '/<html/' ];
    }

    # make sure sla reports contain the graph
    if($report->{'template'} =~ m/^sla_/mx) {
        push @{$like}, '/Width 610/';
        push @{$like}, '/Height 300/';
    }

    # generate report
    my($fh, $tmpfile) = tempfile();
    TestUtils::test_command({
        cmd  => $BIN.' -a report=9999 --local > '.$tmpfile.'; cat '.$tmpfile,
        like => $like,
    }) or BAIL_OUT("report failed in ".$0);

    # do some tests on the actual pdf if possible
    if(!defined $report->{'type'} or $report->{'type'} eq 'pdf') {
        SKIP: {
            skip("pdf content check require pdftotext (install the poppler-utils package)", 1) if !-x '/usr/bin/pdftotext';
            my $ascii = `/usr/bin/pdftotext -l 1 -f 1 $tmpfile - 2>&1`;
            my $desc  = quotemeta($report->{'desc'});
            like($ascii, qr/$desc/, 'PDF contains description: '.$report->{'desc'});
        };
    }
    unlink($tmpfile);

    # update report
    TestUtils::test_command({
        cmd  => $BIN.' "/thruk/cgi-bin/reports2.cgi?action=update&report=9999"',
        like => ['/^OK - report scheduled for update$/'],
    });
    TestUtils::test_command({
        cmd  => $BIN.' report 9999',
        like => [],
    });
    SKIP: {
        skip("skip mail test with external server", 9) if $ENV{'PLACK_TEST_EXTERNALSERVER_URI'};

        my $mailtestfile = '/tmp/mailtest.'.$$;
        unlink($mailtestfile);
        TestUtils::test_command({
            cmd  => $BIN.' -a reportmail=9999',
            like => ['/mail sent successfully$/'],
            env  => { 'THRUK_MAIL_TEST' => $mailtestfile },
        });
        ok(-s $mailtestfile, 'mail testfile '.$mailtestfile.' does exist');
        if(-s $mailtestfile) {
            my $mail = Thruk::Utils::IO::read($mailtestfile);
            for my $like (@{$mail_like}) {
                like($mail, $like, 'Mail contains: '.$like);
            }
            for my $unlike (@{$mail_unlike}) {
                unlike($mail, $unlike, 'Mail must not contain: '.$unlike);
            }
        }
    };

    # remove report
    TestUtils::test_command({
        cmd  => $BIN.' "/thruk/cgi-bin/reports2.cgi?action=remove&report=9999"',
        like => ['/^OK - report removed$/'],
    });
}

done_testing();
