#!/usr/bin/perl -w

if (@ARGV != 2) {
  die "Usage: $0 <spk2utt> <trials>"
}

%spk2utt = ();

open(SPK2UTT, $ARGV[0]);
while (<SPK2UTT>) {
 @arr = split(/\s+/, $_);
 for my $i (1 .. $#arr) {
   $spk2utt{$arr[0]}[$i-1] = $arr[$i];
 }
}

open(TRIAL, $ARGV[1]);
while (<TRIAL>) {
 @arr = split(/\s+/, $_);
 for $i (0 .. $#{ $spk2utt{$arr[0]} }){
   print "$spk2utt{$arr[0]}[$i] $arr[1] $arr[2]\n";
 }
}
