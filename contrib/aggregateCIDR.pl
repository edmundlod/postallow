#!/usr/bin/env perl
#
# Vendored from nabbi/route-summarization:
# https://github.com/nabbi/route-summarization
#
# Copyright (c) 2021-2026 Nic Boet
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# See LICENSES/MIT-route-summarization.txt for the full license text.
#
# inspired by a script by Adrian Popa: http://adrianpopagh.blogspot.com/2008/03/route-summarization-script.html -- see LICENSE
use strict;
use warnings;
use Net::CIDR::Lite;
use Getopt::Long;

GetOptions(
    's|spf'   => \my $spf,
    'q|quiet' => \my $quiet,
    'help'  => \my $help
) or die "Error in command line arguments\n";

if ($help) {
    print "usage: $0\n";
    print "\t-h|--help\tprint usage\n";
    print "\t-q|--quiet\tsuppress outputs\n";
    print "\t-s|--spf\tadd support for parsing spf prefixes\n";
    print "\nAggregates IPv4/IPv6 CIDR prefixes read from stdin into their minimal\n";
    print "covering set, one prefix per line, terminated by CTRL+D.\n\n";
    print "You can also pipe a file in instead of typing interactively, e.g.:\n";
    print "\tcat cidr.txt | $0\n";
    exit;
}

if (!$quiet) { print "# One IP/CIDR per line, e.g. 1.2.3.0/24 -- press CTRL+D when done.\n"; }

my $cidr4 =Net::CIDR::Lite->new;
my $cidr6 =Net::CIDR::Lite->new;

while (<>) {
    my $line = $_;
    chomp $line;

    $line =~ s/^\s*(.*?)\s*$/$1/;

    next if $line eq '';

    if ($spf) {
        $line =~ s/^ip[46]://;
    }

    if( $line =~ m/^(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)\/(\d\d?)$/ &&
                  ( $1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 && $5 <=32) ) {
        $cidr4->add_any($line);

    } elsif( $line =~ m/^(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)$/ &&
                  ( $1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255) ) {
        $cidr4->add("$line/32");

    } elsif( $line =~ m/:/ ) {
        eval {$cidr6->add_any($line)};
        if ($@) {
            if (!$quiet) { print STDERR "# Ignoring IPv6: $line\n"; }
        }

    } else {
        if (!$quiet) { print STDERR"# Ignoring: $line\n"; }
    }
}

my @cidr4_list = $cidr4->list;
my @cidr6_list = $cidr6->list;
if (!$quiet) { print "# Summarized prefixes:\n"; }
foreach my $item4(@cidr4_list){
    $item4 =~ s/\/32$//;
    if ($spf) { print "ip4:"; }
    print "$item4\n";
}
foreach my $item6(@cidr6_list){
    if ($spf) { print "ip6:"; }
    print "$item6\n";
}
