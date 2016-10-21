#!/usr/bin/perl -w

if ($#ARGV == 3) {
  $lexicon_file = $ARGV[0];
  $text_file = $ARGV[1];
  $filtered_text_file = $ARGV[2];
  $oov_file = $ARGV[3];
} else {
  print STDERR ("Usage: $0 lexicon text new_text oov\n");
  exit(1);
}

open(LEXF, $lexicon_file) || die "Unable to open lexicon file $lexicon_file";

open(TEXTF, $text_file) || die "Unable to open text file $text_file";

open(FILTEREDF, "> $filtered_text_file") || die "Unable to open filtered text file $filtered_text_file";

open(OOVF, "> $oov_file") || die "Unable to open oov file $oov_file";

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
      $line = "$line $subi";
      if (not exists $lexicon{$subi}){
        $oov{$subi} += 1;
        $keep = 0;
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


