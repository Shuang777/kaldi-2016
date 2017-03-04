#!/usr/bin/perl

# This script reads in a lexicon and accumulate statistics from it to construct FSTs

$cmdline = join " ", $0, @ARGV;
print $cmdline . "\n";

if ($#ARGV != 2) {
  print STDERR "Usage: $0 <lexicon> <phone.syms> <dir>\n";
  exit(1);
}

$lexicon = $ARGV[0];
$phoneseq = $ARGV[1];
$dir = $ARGV[2];

open(LEX, $lexicon) || die("Failed to open lexicon file $lexicon\n");

$patterntotal = 0;
%patterncount = ();
%phone2onc = ("<eps>" => {});
%syl2pattern = ();

open(LEX_ONC, "> $dir/lexicon_onc.txt") || die "Failed to open $dir/lexicon_onc.txt for writing\n";
while($line = <LEX>) {
  chomp $line;
  ($word, @syls) = split(/\t/, $line);
  $pron = "";
  foreach $syl (@syls) {
    $syl =~ s/^\s+//;
    $syl =~ s/\s+$//;
    @phones = split(/ /, $syl);
    $seen_nucleus = 0;
    @oncs = &mark_syllable(\@phones);
    $pattern = join("", @oncs);
    for ($i = 0; $i <= $#phones; $i++) {
      &register($phones[$i], $oncs[$i]);
    }
    if ($pattern ne "") {
      $patterntotal++;
      $patterncount{$pattern}++;
    }
    $pron = $pron . $syl . " (" . $pattern . ") \t";
    $syl2pattern{$syl} = $pattern;
  }
  print LEX_ONC "$word\t$pron\n";
}
close(LEX_ONC);

open(SYLONC, "> $dir/syl2onc.txt") || die("Failed to open $dir/syl2onc.txt for writing\n");
for $syl (keys %syl2pattern) {
  print SYLONC "$syl $syl2pattern{$syl}\n";
}
close(SYLONC);

# Create the mapper fst
$statecounter=1;
open(PHONESEQ, "$phoneseq") || die("Failed to open $phoneseq for reading");
open(PHONESEQ2PHONEONC, "> $dir/phoneseq2phoneonc.txt") || die("Failed to open $dir/phoneseq2phoneonc.txt for writing");

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
    if (defined($phone2onc{$sparts[$si]})) {
      foreach $t (keys %{$phone2onc{$sparts[$si]}}) {
        print PHONESEQ2PHONEONC "$cur $next $printsym $sparts[$si]/$t\n";
      }
    } else {
      print PHONESEQ2PHONEONC "$cur $next $printsym <eps>\n";
    }
    $cur=$next;
    $printsym="<eps>";
  }
}

print PHONESEQ2PHONEONC "0\n";
close(PHONESEQ);
close(PHONESEQ2PHONEONC);


# ONC structure acceptor
open (ONCCONSTRAINT, "> $dir/onc_constraint.txt") || die("Failed to open file $dir/onc_constraint.txt");
open (ONCCONSTRAINTFST, "> $dir/onc_constraint.fst.txt") || die("Failed to open file $dir/onc_constraint.fst.txt");
# We also want to keep track of syllable boundarys, so we construct an additional FST for syllable boundary
open (ONCBOUNDARY, "> $dir/onc_boundary.fst.txt") || die("Failed to open file $dir/onc_boundary.fst.txt");
$statecounter=1;
$lpt = log($patterntotal);
foreach $pattern (keys %patterncount) {
  @parts = split(//, $pattern);
  print ONCCONSTRAINT "$pattern $patterncount{$pattern}\n";
  $cur = 0;
  for ($pix=0;$pix<=$#parts;$pix++) {
    if ($pix==$#parts) {
      $next=0;
      $outsymbol = $parts[$pix] . "=";   # we add syllable boundary here
    } else {
      $next=$statecounter;
      $statecounter++;
      $outsymbol = $parts[$pix];
    }
    if ($pix==0) {
      $score=sprintf("%.6g",$lpt-log($patterncount{$pattern}));
    } else {
      $score=0;
    }
    print ONCCONSTRAINTFST "$cur $next $parts[$pix] $score\n";
    print ONCBOUNDARY "$cur $next $parts[$pix] $outsymbol $score\n";
    $cur=$next;
  }
}
close(ONCCONSTRAINT);
print ONCCONSTRAINTFST "0\n";
close(ONCCONSTRAINTFST);
print ONCBOUNDARY "0\n";
close(ONCBOUNDARY);


# write out onc symbols
open(ONCSYMS, " > $dir/onc.syms") || die("Failed to open $dir/onc.syms for writing");
print ONCSYMS "<eps>\t0\n";
print ONCSYMS "O\t1\n";
print ONCSYMS "N\t2\n";
print ONCSYMS "C\t3\n";
close(ONCSYMS);

open(ONCBOUNDARYSYMS, "> $dir/onc_boundary.syms") || die("Failed to open $dir/onc_boundary.syms for writing");
print ONCBOUNDARYSYMS "<eps>\t0\n";
print ONCBOUNDARYSYMS "O\t1\n";
print ONCBOUNDARYSYMS "N\t2\n";
print ONCBOUNDARYSYMS "C\t3\n";
print ONCBOUNDARYSYMS "N=\t4\n";
print ONCBOUNDARYSYMS "C=\t5\n";
close(ONCBOUNDARYSYMS);

# write the PH/ONC to ONC mapper
open(PHONEONC2ONC, " > $dir/phoneonc2onc.txt") || die("Failed to open $dir/phoneonc2onc.txt for writing");
@phoneoncsyms=();
foreach $phone (keys %phone2onc) {
  @t=keys %{$phone2onc{$phone}};
  if ($#t<0) {  # <eps> symbol
    push(@phoneoncsyms, $phone);
  } else {
    foreach $t (@t) {
      push(@phoneoncsyms,"$phone/$t");
      print PHONEONC2ONC "0 0 $phone/$t $t\n";
    }
  }
}
print PHONEONC2ONC "0\n";
close(PHONEONC2ONC);

# write out PH/ONC symbols
open(PHONEONCSYMS, " > $dir/phoneonc.syms") || die("Failed to open $dir/onc.syms for writing");
@phoneoncsymssort=sort bysymbol @phoneoncsyms;
for($i=0;$i<=$#phoneoncsymssort;$i++) {
  print PHONEONCSYMS "$phoneoncsymssort[$i]\t$i\n";
}
close(PHONEONCSYMS);

print "$0: done!\n";
exit(0);

sub phoneclass {
  my $a=shift(@_);

#  if ($a =~ /^[aeiuo36AEIOUV\{\@]/) {
  if ($a =~ /^[aeiuoAEIOUVyYQ\{\}\@1236789M]/) {
    return "V";
#  } elsif ($a =~ /^[[:alnum:]\?]/) {
  } else {
    return "C";
  } 
}

sub register {
  my $phone=shift(@_);
  my $class=shift(@_);

  $phone2onc{$phone}={} if !defined($phone2onc{$phone});
  $phone2onc{$phone}->{$class}=1;
}

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

sub get_phone_rank {
  my $a=shift(@_);

  if ($a =~ /^[aeiuoAEIOUVyYQ\{\}\@1236789M]/) {
    return 1;
  } elsif ($a =~ /^[mFnJN]/) {
    return 2;
  } else {
    return 3;
  }
}

sub minindex {
  my( $aref, $idx_min ) = ( shift, 0 );
  for my $i (1 .. $#{$aref}) {
    if ($aref->[$i] < $aref->[$idx_min]) {
      $idx_min = $i;
    }
  }
  return $idx_min;
}

sub mark_syllable{
  my $phones_ref = @_;
  my $phones = @{ $phones_ref };
  my @phone_ranks;
  foreach my $phone (@phones) {
    push(@phone_ranks, &get_phone_rank($phone));
  }
  $min_index = &minindex(\@phone_ranks);
  my @oncs = ("X") x ($#phone_ranks+1);
  $oncs[$min_index] = "N";
  $last_min_index = $min_index;
  for ($i = $min_index+1; $i <= $#phone_ranks; $i++) {
    if ($phone_ranks[$i] == $phone_ranks[$min_index]) {
      $oncs[$i] = "N";
      $last_min_index = $i;
    } else {
      last;
    }
  }
  for ($i = 0; $i < $min_index; $i++) {
    $oncs[$i] = "O";
  }
  for ($i = $last_min_index+1; $i <= $#phone_ranks; $i++) {
    $oncs[$i] = "C";
  }
  return @oncs;
}
