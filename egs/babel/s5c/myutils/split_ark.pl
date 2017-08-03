#!/usr/bin/env perl

if ($#ARGV != 0) {
  die("Usage: copy-feats scp:feats.scp ark,t:- | split_ark.pl <out-dir>");
}

$outdir= shift @ARGV;

while (<>) {
  if ($_ =~ /\[/) {
    @A = split(" ", $_);
    $filename = $A[0];
    open(ARKF, "> $outdir/$filename.ark")
  } elsif ($_ =~ /]/) {
    $_ =~ s/ ]//;
    print ARKF $_;
    close ARKF;
  } else {
    print ARKF $_;
  }
}
