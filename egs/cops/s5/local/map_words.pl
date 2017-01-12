#!/usr/bin/perl -w
# map words as given in map.list

if ($#ARGV == 2) {
  $ori_text_file = $ARGV[0];
  $map_file = $ARGV[1];
  $new_text_file = $ARGV[2];
} else {
  die "Usage: $0 text map.list new_text";
}

open(ORI_TEXTF, $ori_text_file) || die "Unable to open ori_text_file $ori_text_file";
open(MAPF, $map_file) || die "Unable to open map file $map_file";
open(NEW_TEXTF, "> $new_text_file") || die "Unable to open new_text_file $new_text_file";

%map = ();
while (<MAPF>) {
  @A = split /\s+/, $_;
  if ($#A != 1) {
    die "$_ not correct format!";
  }
  $map{$A[0]} = $A[1];
}

while (<ORI_TEXTF>) {
  @A = split /\s+/, $_, 2;
  $line = $A[0];
  @words = split /\s+/, $A[1];
  if ($#words < 0) {
    next;
  }
  foreach my $i (@words) {
    if (exists $map{$i}) {
      $line = "$line $map{$i}";
    } else {
      $line = "$line $i";
    }
  }
  print NEW_TEXTF "$line\n";
}
