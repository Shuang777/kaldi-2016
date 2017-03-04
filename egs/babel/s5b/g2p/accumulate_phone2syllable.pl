#!/usr/bin/perl

# This script reads in a lexicon and accumulate statistics from it to construct FSTs

$cmdline = join " ", $0, @ARGV;
print $cmdline . "\n";

if ($#ARGV != 2) {
  print STDERR "Usage: $0 <lexicon> <phone.syms> <dir>";
  exit(1);
}

$lexicon = $ARGV[0];
$phoneseq = $ARGV[1];
$dir = $ARGV[2];

%sylscount = ("<eps>" => 1);
$sylstotal = 0;
open(LEX, $lexicon) || die("Failed to open lexicon file $lexicon\n");
while($line = <LEX>) {
  chomp $line;
  ($word, @syls) = split(/\t/, $line);
  foreach $syl (@syls) {
    $syl =~ s/^\s+//;
    $syl =~ s/\s+$//;
    $syl =~ s/ /=/g;
    $sylscount{$syl}++;
    $sylstotal++;
  }
}
close(LEX);

open(PHONE2SYL, "> $dir/phone2syl.txt") || die("Failed to open $dir/phone2syl.txt for writting\n");
$lst = log($sylstotal);
$statecounter=1;
%phonesyms = ();
for $syl (keys %sylscount) {
  @phones = split(/=/, $syl);
  $cur = 0;
  for ($i = 0; $i <= $#phones; $i++) {
    if ($i == $#phones) {
      $next = 0;
    } else {
      $next=$statecounter;
      $statecounter++;
    }
    $outsymbol = "<eps>";
    $score = 0;
    if ($i == 0) {
      $outsymbol = $syl;
      $score = sprintf("%.6g", $lst - log($sylscount{$syl}));
    }
    print PHONE2SYL "$cur $next $phones[$i] $outsymbol $score\n";
    $phonesyms{$phones[$i]} = 1;
    $cur=$next;
  }
}
print PHONE2SYL "0\n";
close(LEX_ONC);

# Create the mapper fst
$statecounter=1;
open(PHONESEQ, "$phoneseq") || die("Failed to open $phoneseq for reading");
open(PHONESEQ2PHONE, "> $dir/phoneseq2phone.txt") || die("Failed to open $dir/phoneseq2phone.txt for writing");
while(<PHONESEQ>) {
  chomp;
  ($sym, $num) = split;
  if ($sym eq "|") {
    @sparts=($sym);
  } else {
    @sparts=split(/\|/,$sym);
  }

  # iterate over phones and create an fst
  $cur = 0;
  $printsym = $sym;
  for ($si = 0; $si <= $#sparts; $si++) {
    if ($si == $#sparts) {
      $next = 0;
    } else {
      $next = $statecounter;
      $statecounter++;
    }
    print PHONESEQ2PHONE "$cur $next $printsym $sparts[$si]\n";
    $phonesyms{$sparts[$si]} = 1;
    $cur=$next;
    $printsym="<eps>";
  }
}
print PHONESEQ2PHONE "0\n";
close(PHONESEQ);
close(PHONESEQ2PHONE);

open(PHONESYMS, "> $dir/phone.syms") || die("Failed to open $dir/phone.syms for writing");
@phonesymssort = sort bysymbol (keys %phonesyms);
for ($i = 0; $i <= $#phonesymssort; $i++) {
  print PHONESYMS "$phonesymssort[$i]\t$i\n";
}
close(PHONESYMS);

open(SYLSYMS, "> $dir/syllable.syms") || die("Failed to open $dir/syllable.syms for writing");
@sylsymssort = sort bysymbol (keys %sylscount);
for ($i = 0; $i <= $#sylsymssort; $i++) {
  print SYLSYMS "$sylsymssort[$i]\t$i\n";
}
close(SYLSYMS);

print "$0: done\n";
exit(0);

sub bysymbol {
  if ($a eq $b) {
    return 0;
  } elsif ($a eq "<eps>") {
    return -1;
  } elsif ($b eq "<eps>") {
    return 1;
  } elsif ($a eq "|") {
    return -1;
  } elsif ($b eq "|") {
    return 1;
  } elsif ($a eq "<phi>") {
    return -1;
  } elsif ($b eq "<phi>") {
    return 1;
  } else {
    return $a cmp $b;
  }
}
