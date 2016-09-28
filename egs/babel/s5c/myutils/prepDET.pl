#!/usr/bin/perl -w

if (@ARGV != 3) {
  die "Usage: $0 <label-file> <score-file> <dir>\n";
}
$labelFile = $ARGV[0];
$scoreFile = $ARGV[1];
$dir = $ARGV[2];

open(LABELF, "<$labelFile") || die "Unable to open input label file $labelFile\n";
open(SCOREF, "<$scoreFile") || die "Unable to open input score file $scoreFile\n";
open(TRUEF, ">$dir/true.scores") || die "Unable to open output score file true.scores\n";
open(IMPOSTERF, ">$dir/imposter.scores") || die "Unable to open output score file imposter.scores\n";

while(<LABELF>) {
  @A = split(/\s+/, $_);
  if ($A[2] eq "target") {
    $label{$A[1]} = $A[0];
  }
}

while(<SCOREF>) {
  @A = split(/\s+/, $_);
  if (exists $label{$A[1]} and ($A[0] eq $label{$A[1]})) {
    print TRUEF $A[2], "\n";
  } else {
    print IMPOSTERF $A[2], "\n";
  }
}
