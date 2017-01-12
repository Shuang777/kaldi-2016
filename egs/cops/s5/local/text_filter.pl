#!/usr/bin/perl -w
# check if words appear in lexicon, if not, break it and check, record oov

if ($#ARGV == 4) {
  $map_file = $ARGV[0];
  $lexicon_file = $ARGV[1];
  $text_file = $ARGV[2];
  $filtered_text_file = $ARGV[3];
  $oov_file = $ARGV[4];
} else {
  die "Usage: $0 lexicon text new_text oov\n";
}

$map_to_unk = 1;

open(MAPF, $map_file) || die "Unable to open map file $map_file";
open(LEXF, $lexicon_file) || die "Unable to open lexicon file $lexicon_file";
open(TEXTF, $text_file) || die "Unable to open text file $text_file";
open(FILTEREDF, "> $filtered_text_file") || die "Unable to open filtered text file $filtered_text_file";
open(OOVF, "| sort -k2 -n -r > $oov_file") || die "Unable to open oov file $oov_file";

%map = ();
while (<MAPF>) {
  @A = split /\s+/, $_;
  if ($#A != 1) {
    die "$_ not correct format!";
  }
  $map{$A[0]} = $A[1];
}


%lexicon = ();

while (<LEXF>) {
  @A = split /\s+/, $_, 2;
  $lexicon{$A[0]} = $A[1];
}

$count = 0;
$count_filtered = 0;

%oov = ();
while (<TEXTF>) {
  $count = $count + 1;
  @A = split /\s+/, $_, 2;
  $line = $A[0];
  @words = split /\s+/, $A[1];
  if ($#words < 0) {
    next;
  }
  $keep = 1;
  foreach my $i (@words) {
    if (exists $lexicon{$i}) {
      $line = "$line $i";
      next;
    } 
    @sep = split /-/, $i;
    foreach my $subi (@sep) {
      if (exists $lexicon{$subi}) {
        $line = "$line $subi";
      } elsif (exists $map{$subi}) {
        $line = "$line $map{$subi}";
      } else {
        $oov{$subi} += 1;
        if ($map_to_unk) {
          $line = "$line <unk>";
        } else {
          $keep = 0;
          #print "$_";
        }
      }  
    }
    if ($keep == 0) {
      last;
    }
  }
  if ($keep == 1) {
    print FILTEREDF "$line\n";
  } else {
    $count_filtered = $count_filtered + 1;
  }
}

foreach my $word (keys %oov) {
  print OOVF "$word $oov{$word}\n";
}

print "$count_filtered out of $count utterances filtered, ", $count - $count_filtered, " remaining\n";


