use warnings;
use strict;
use Test::More;

chomp(my $arch = `uname -s`);
plan skip_all => 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.' unless $ENV{TEST_AUTHOR};
plan skip_all => 'Does not work on OSX' if $arch eq 'Darwin';

my $cmd = "./script/thruk_set_standard_header check";
ok(1, $cmd);
my $res = `$cmd 2>&1`;
my $rc  = $?;

fail("$cmd failed with: rc=$rc") if $rc != 0;
fail("$cmd found issues:\n$res") if $res ne "";

done_testing();
