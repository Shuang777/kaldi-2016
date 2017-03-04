#!/usr/bin/perl

$DELIMITER="\t ";

while($line = <>) {
  chomp $line;
  ($word, $pron) = split(/\t/, $line);
  $state=0;
  @phones = split(/\s/, $pron);
  print "$word\t";
  foreach $p (@phones) {
    if ($p=~s/\/O$//) {
      if ($state==1) {
        print "\t";
      }
      $state=0;
      $p=~s/\/O$//;
    } elsif ($p=~/\/N$/) {
      if ($state==1) {
        print "\t";
      }
      $state=1;
      $p=~s/\/N$//;
    } else {
      $state=1;
      $p=~s/\/C$//;
    }
    print " $p";

  }
  print "\n";
}
