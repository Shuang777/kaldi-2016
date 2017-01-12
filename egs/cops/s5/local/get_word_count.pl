#!/usr/bin/perl -w
use strict;
use warnings;
 
my %count;
while (my $line = <>) {
  chomp $line;
  foreach my $str (split /\s+/, $line) {
    $count{$str}++;
  }
}
 
foreach my $str (sort keys %count) {
  printf "%s %s\n", $str, $count{$str};
}
